/*
  nvlocale — ID-based localization for NVGT / AngelScript.
  Version 0.1.0

  Why IDs instead of templates:
  a game string is usually assembled from several pieces. Translating each
  piece separately ("%1 has %2 %3") produces mixed-language garbage, because
  word order, case and number agreement live in the whole sentence. Here the
  whole sentence is one ID, and the pieces are positional arguments:
  {0}, {1}, ... The translator sees the full sentence in the full language.

  Why no DSL for plurals:
  CLDR plural rules are not text, they are a finite table. About twenty rule
  functions cover the languages an indie game is realistically translated
  into. They are written once, here, and never travel to translators.

  Catalog format (.lng, UTF-8):
    # comment lines start with # or ; or //
    id[=]text with {0} and {1}
    bag.items.one[=]В сумке {0} предмет.
    bag.items.few[=]В сумке {0} предмета.
    bag.items.many[=]В сумке {0} предметов.
  "[=]" is the same separator used by the Life in Nature language packs.
  A plain "=" works too. Later definitions override earlier ones, so a
  second file can patch a base catalog.

  Usage:
    #include "nvlocale.as"
    using loc;
    void main() {
      init("catalogs", "ru");            // dir, language ("" = auto)
      screen_reader_speak(t("menu.start"));
      screen_reader_speak(t("bag.recv", "Mila", t("item.whistle")));
      screen_reader_speak(tn("bag.items", 5));   // "В сумке 5 предметов."
    }
*/

namespace loc {

// ---------------------------------------------------------------------------
// constants
// ---------------------------------------------------------------------------

const int R_OTHER_ONLY = 0;   // ja zh ko th vi id ms
const int R_ONE        = 1;   // en de nl sv da no fi et hu el es it ru fallback
const int R_FR         = 2;   // fr pt hy
const int R_RU         = 3;   // ru uk be
const int R_PL         = 4;   // pl
const int R_CS         = 5;   // cs sk
const int R_SL         = 6;   // sl
const int R_LT         = 7;   // lt
const int R_LV         = 8;   // lv
const int R_GA         = 9;   // ga
const int R_RO         = 10;  // ro
const int R_AR         = 11;  // ar
const int R_HE         = 12;  // he iw
const int R_IS         = 13;  // is
const int R_MK         = 14;  // mk
const int R_MT         = 15;  // mt
const int R_CY         = 16;  // cy
const int R_BR         = 17;  // br
const int R_FA         = 18;  // fa
const int R_HI         = 19;  // hi bn
const int R_BG         = 20;  // bg
const int R_SR         = 21;  // sr hr bs
const int R_DA         = 22;  // da

// ---------------------------------------------------------------------------
// state
// ---------------------------------------------------------------------------

dictionary@ base_catalog = null;    // language of last resort (usually en)
dictionary@ active_catalog = null;  // current language
string active_lang = "en";
string path_prefix = "lang";
string[] missing_list;
dictionary missing_seen;
string[] error_list;
int error_total = 0;

// ---------------------------------------------------------------------------
// small string helpers
// ---------------------------------------------------------------------------

// NOTE: the NVGT string API has find()/substr()/erase()/lower()/
// trim_whitespace()/starts_with(), but not findFirst(). Indexing s[i] yields
// a one-character const string, not an integer.

string replace_first(const string &in s, const string &in from, const string &in to) {
	int p = s.find(from);
	if (p < 0) return s;
	return s.substr(0, uint(p)) + to + s.substr(uint(p) + from.length());
}

string pad_left(const string &in s, uint width, const string &in fill) {
	string res = s;
	while (res.length() < width) res = fill + res;
	return res;
}

// "ru-RU" / "ru_RU" / "RU" -> "ru"; unknown separators and empties -> "".
string normalize_lang(const string &in code) {
	string raw = code.trim_whitespace().lower();
	int cut = raw.find("-");
	int cut2 = raw.find("_");
	int cut3 = raw.find(".");
	if (cut2 >= 0 && (cut < 0 || cut2 < cut)) cut = cut2;
	if (cut3 >= 0 && (cut < 0 || cut3 < cut)) cut = cut3;
	if (cut >= 0) raw = raw.substr(0, uint(cut));
	const string allowed = "abcdefghijklmnopqrstuvwxyz0123456789";
	for (uint i = 0; i < raw.length(); i++) {
		if (allowed.find(raw.substr(i, 1)) < 0) return "";
	}
	return raw;
}

// ---------------------------------------------------------------------------
// escaping
// ---------------------------------------------------------------------------

// Unescaping and placeholder substitution happen in ONE pass over the raw
// catalog text. This matters: if {{0}} were unescaped first, the resulting
// literal {0} would be substituted on the next pass. Here {{ always yields a
// literal brace that is never re-scanned.
//
// Replaces {0} {1} ... with args[0], args[1] ... Unknown indices are kept
// verbatim so a translation bug is visible instead of silent.
string format_text(const string &in text, const string[] &in args) {
	string res;
	uint i = 0;
	uint n = text.length();
	uint nargs = args.length();
	while (i < n) {
		string c = text.substr(i, 1);
		if (c == "\\" && i + 1 < n) {
			string d = text.substr(i + 1, 1);
			if (d == "n") { res += "\n"; i += 2; continue; }
			if (d == "t") { res += "\t"; i += 2; continue; }
			if (d == "r") { res += "\r"; i += 2; continue; }
			if (d == "\\") { res += "\\"; i += 2; continue; }
			// unknown escape: keep the backslash as written
			res += c;
			i++;
			continue;
		}
		if (c == "{") {
			if (i + 1 < n && text.substr(i + 1, 1) == "{") { res += "{"; i += 2; continue; }
			uint j = i + 1;
			uint start = j;
			while (j < n && "0123456789".find(text.substr(j, 1)) >= 0) j++;
			if (j > start && j < n && text.substr(j, 1) == "}") {
				uint idx = 0;
				bool overflow = false;
				for (uint k = start; k < j; k++) {
					if (idx > 429496728) { overflow = true; break; }
					idx = idx * 10 + uint("0123456789".find(text.substr(k, 1)));
				}
				if (!overflow && idx < nargs) {
					res += args[idx];
					i = j + 1;
					continue;
				}
				res += text.substr(i, int(j + 1 - i));
				i = j + 1;
				continue;
			}
		}
		if (c == "}" && i + 1 < n && text.substr(i + 1, 1) == "}") { res += "}"; i += 2; continue; }
		res += c;
		i++;
	}
	return res;
}

// ---------------------------------------------------------------------------
// numbers
// ---------------------------------------------------------------------------

bool uses_comma_decimal(const string &in lang) {
	return lang == "ru" || lang == "uk" || lang == "be" || lang == "bg"
		|| lang == "de" || lang == "el" || lang == "es" || lang == "et"
		|| lang == "fi" || lang == "fr" || lang == "hr" || lang == "hu"
		|| lang == "id" || lang == "is" || lang == "it" || lang == "lt"
		|| lang == "lv" || lang == "nl" || lang == "no" || lang == "nb"
		|| lang == "nn" || lang == "pl" || lang == "pt" || lang == "ro"
		|| lang == "sk" || lang == "sl" || lang == "sr" || lang == "bs"
		|| lang == "cs" || lang == "da" || lang == "tr" || lang == "vi"
		|| lang == "ca";
}

// Locale-aware number: 7 -> "7", 7.5 -> "7.5" (ru: "7,5"), 7.500 -> "7.5".
// precision -1 means "as many decimals as needed, trailing zeros trimmed".
string num(double v, int precision = -1) {
	string s;
	if (precision >= 0) {
		uint p = uint(precision > 9 ? 9 : precision);
		double a = (v < 0 ? -v : v);
		double scale_d = 1.0;
		int64 scale = 1;
		for (uint k = 0; k < p; k++) {
			scale_d *= 10.0;
			scale *= 10;
		}
		if (a * scale_d < 9.0e18) {
			int64 scaled = int64(floor(a * scale_d + 0.5));
			int64 ip = scaled / scale;
			int64 fp = scaled % scale;
			s = string(ip);
			if (p > 0) s += "." + pad_left(string(fp), p, "0");
			if (v < 0 && scaled != 0) s = "-" + s;
		} else {
			s = string(v);
		}
	} else {
		// string(double) already produces the shortest round-trip form:
		// 7 -> "7", 7.5 -> "7.5", 0.1 + 0.2 -> "0.3".
		s = string(v);
	}
	if (uses_comma_decimal(active_lang)) s = replace_first(s, ".", ",");
	return s;
}

// ---------------------------------------------------------------------------
// CLDR plural rules
// ---------------------------------------------------------------------------

int rule_for(const string &in lang) {
	if (lang == "ja" || lang == "zh" || lang == "ko" || lang == "th"
		|| lang == "vi" || lang == "id" || lang == "ms" || lang == "lo"
		|| lang == "my" || lang == "km" || lang == "jv" || lang == "su"
		|| lang == "yue") return R_OTHER_ONLY;
	if (lang == "fr" || lang == "pt" || lang == "hy") return R_FR;
	if (lang == "ru" || lang == "uk" || lang == "be") return R_RU;
	if (lang == "bg") return R_BG;
	if (lang == "sr" || lang == "hr" || lang == "bs") return R_SR;
	if (lang == "pl") return R_PL;
	if (lang == "cs" || lang == "sk") return R_CS;
	if (lang == "sl") return R_SL;
	if (lang == "lt") return R_LT;
	if (lang == "lv") return R_LV;
	if (lang == "ga") return R_GA;
	if (lang == "ro") return R_RO;
	if (lang == "ar") return R_AR;
	if (lang == "he" || lang == "iw") return R_HE;
	if (lang == "is") return R_IS;
	if (lang == "mk") return R_MK;
	if (lang == "mt") return R_MT;
	if (lang == "cy") return R_CY;
	if (lang == "br") return R_BR;
	if (lang == "fa") return R_FA;
	if (lang == "hi" || lang == "bn") return R_HI;
	if (lang == "da") return R_DA;
	return R_ONE;
}

// Returns zero / one / two / few / many / other.
string plural_category(double n, const string &in lang = "") {
	string language = normalize_lang(lang);
	if (language == "") language = active_lang;
	double an = (n < 0 ? -n : n);
	if (an > 9.0e18) return "other";
	bool frac = (an != floor(an));
	int64 i64 = int64(floor(an));
	int i10 = int(i64 % 10);
	int i100 = int(i64 % 100);
	int rule = rule_for(language);

	if (rule == R_OTHER_ONLY) return "other";

	if (rule == R_ONE) {
		if (an == 1) return "one";
		return "other";
	}

	if (rule == R_DA) {
		// CLDR da: n = 1 or t != 0, i.e. any fraction is "one".
		if (an == 1 || frac) return "one";
		return "other";
	}

	if (rule == R_FR) {
		// CLDR: i = 0,1 — the fraction does not matter (1.5 is "one").
		if (i64 == 0 || i64 == 1) return "one";
		return "other";
	}

	if (rule == R_RU) {
		if (frac) return "other";
		if (i10 == 1 && i100 != 11) return "one";
		if (i10 >= 2 && i10 <= 4 && !(i100 >= 12 && i100 <= 14)) return "few";
		return "many";
	}

	if (rule == R_BG) {
		if (frac) return "other";
		if (i10 == 1 && i100 != 11) return "one";
		return "other";
	}

	if (rule == R_SR) {
		// CLDR also distinguishes fractional forms via the f operand;
		// a double does not know its visible fraction digits, so any
		// non-integer is treated as "other" here (documented limitation).
		if (frac) return "other";
		if (i10 == 1 && i100 != 11) return "one";
		if (i10 >= 2 && i10 <= 4 && !(i100 >= 12 && i100 <= 14)) return "few";
		return "other";
	}

	if (rule == R_PL) {
		if (frac) return "other";
		if (i64 == 1) return "one";
		if (i10 >= 2 && i10 <= 4 && !(i100 >= 12 && i100 <= 14)) return "few";
		return "many";
	}

	if (rule == R_CS) {
		if (frac) return "many";
		if (i64 == 1) return "one";
		if (i64 >= 2 && i64 <= 4) return "few";
		return "other";
	}

	if (rule == R_SL) {
		if (frac) return "few";
		if (i100 == 1) return "one";
		if (i100 == 2) return "two";
		if (i100 == 3 || i100 == 4) return "few";
		return "other";
	}

	if (rule == R_LT) {
		if (frac) return "many";
		if (i10 == 1 && !(i100 >= 11 && i100 <= 19)) return "one";
		if (i10 >= 2 && i10 <= 9 && !(i100 >= 11 && i100 <= 19)) return "few";
		return "other";
	}

	if (rule == R_LV) {
		if (frac) return "other";
		if (i10 == 0 || (i100 >= 11 && i100 <= 19)) return "zero";
		if (i10 == 1 && i100 != 11) return "one";
		return "other";
	}

	if (rule == R_GA) {
		if (frac) return "other";
		if (i64 == 1) return "one";
		if (i64 == 2) return "two";
		if (i64 >= 3 && i64 <= 6) return "few";
		if (i64 >= 7 && i64 <= 10) return "many";
		return "other";
	}

	if (rule == R_RO) {
		if (frac) return "few";
		if (i64 == 1) return "one";
		if (i64 == 0 || (i100 >= 2 && i100 <= 19)) return "few";
		return "other";
	}

	if (rule == R_AR) {
		if (frac) return "other";
		if (i64 == 0) return "zero";
		if (i64 == 1) return "one";
		if (i64 == 2) return "two";
		if (i100 >= 3 && i100 <= 10) return "few";
		if (i100 >= 11 && i100 <= 99) return "many";
		return "other";
	}

	if (rule == R_HE) {
		if (frac) return "other";
		if (i64 == 1) return "one";
		if (i64 == 2) return "two";
		if (i64 != 0 && i10 == 0) return "many";
		return "other";
	}

	if (rule == R_IS) {
		if (frac) return "one";
		if (i10 == 1 && i100 != 11) return "one";
		return "other";
	}

	if (rule == R_MK) {
		if (frac) return "other";
		if (i10 == 1 && i100 != 11) return "one";
		return "other";
	}

	if (rule == R_MT) {
		if (frac) return "other";
		if (i64 == 1) return "one";
		if (i64 == 0 || (i100 >= 2 && i100 <= 10)) return "few";
		if (i100 >= 11 && i100 <= 19) return "many";
		return "other";
	}

	if (rule == R_CY) {
		if (frac) return "other";
		if (i64 == 0) return "zero";
		if (i64 == 1) return "one";
		if (i64 == 2) return "two";
		if (i64 == 3) return "few";
		if (i64 == 6) return "many";
		return "other";
	}

	if (rule == R_BR) {
		if (frac) return "other";
		if (i10 == 1 && i100 != 11 && i100 != 71 && i100 != 91) return "one";
		if (i10 == 2 && i100 != 12 && i100 != 72 && i100 != 92) return "two";
		if ((i10 == 3 || i10 == 4 || i10 == 9)
			&& !(i100 >= 10 && i100 <= 19)
			&& !(i100 >= 70 && i100 <= 79)
			&& !(i100 >= 90 && i100 <= 99)) return "few";
		if (i64 != 0 && i64 % 1000000 == 0) return "many";
		return "other";
	}

	if (rule == R_FA || rule == R_HI) {
		if (i64 == 0 || an == 1) return "one";
		return "other";
	}

	return "other";
}

// ---------------------------------------------------------------------------
// catalogs
// ---------------------------------------------------------------------------

void record_error(const string &in source, uint line, const string &in message) {
	error_total++;
	error_list.insert_last(source + ":" + string(line) + ": " + message);
}

bool add_line(dictionary@ d, const string &in line, uint lineno, const string &in source) {
	string s = line.trim_whitespace();
	if (s == "") return true;
	if (lineno == 1 && s.starts_with("\xEF\xBB\xBF")) s = s.substr(3); // UTF-8 BOM
	s = s.trim_whitespace();
	if (s == "") return true;
	if (s.starts_with("#") || s.starts_with(";")) return true;
	if (s.starts_with("//")) return true;
	int sep = s.find("[=]");
	int width = 3;
	if (sep < 0) {
		sep = s.find("=");
		width = 1;
	}
	if (sep < 0) {
		record_error(source, lineno, "missing separator ([=] or =)");
		return false;
	}
	string key = s.substr(0, uint(sep)).trim_whitespace();
	string value = s.substr(uint(sep) + uint(width)).trim_whitespace();
	if (key == "") {
		record_error(source, lineno, "empty id");
		return false;
	}
	if (key.find(" ") >= 0 || key.find("\t") >= 0) {
		record_error(source, lineno, "id contains whitespace: " + key);
		return false;
	}
	d.set(key, value);
	return true;
}

// Parses a .lng file into d. Returns false when the file cannot be read.
// Syntax problems are collected in error_list, parsing continues.
bool parse_file(const string &in path, dictionary@ d) {
	if (d is null) return false;
	if (!file_exists(path)) return false;
	string content = file_get_contents(path);
	uint pos = 0;
	uint len = content.length();
	uint lineno = 0;
	while (pos < len) {
		int nl = content.find("\n", pos);
		uint end = (nl < 0) ? len : uint(nl);
		string line = content.substr(pos, int(end - pos));
		pos = (nl < 0) ? len : uint(nl) + 1;
		lineno++;
		add_line(d, line, lineno, path);
	}
	return true;
}

// Loads dir/<lang>.lng as the current language. Existing keys are kept if the
// file does not define them; the English base still covers them.
bool load(const string &in lang) {
	string code = normalize_lang(lang);
	if (code == "") return false;
	dictionary@ d = dictionary();
	if (!parse_file(path_prefix + "/" + code + ".lng", d)) return false;
	@active_catalog = d;
	active_lang = code;
	return true;
}

// Loads a specific file as the current language (ignores path_prefix).
bool load_file(const string &in lang, const string &in path) {
	string code = normalize_lang(lang);
	if (code == "") return false;
	dictionary@ d = dictionary();
	if (!parse_file(path, d)) return false;
	@active_catalog = d;
	active_lang = code;
	return true;
}

// Loads the fallback catalog without making it active.
bool load_base(const string &in lang = "en") {
	string code = normalize_lang(lang);
	if (code == "") return false;
	dictionary@ d = dictionary();
	if (!parse_file(path_prefix + "/" + code + ".lng", d)) return false;
	@base_catalog = d;
	return true;
}

bool available(const string &in lang) {
	string code = normalize_lang(lang);
	if (code == "") return false;
	return file_exists(path_prefix + "/" + code + ".lng");
}

// Picks a language from the OS. Prefers a language we have a catalog for.
string detect(const string &in fallback = "en") {
	string[]@ preferred = get_preferred_locales();
	if (preferred !is null) {
		for (uint i = 0; i < preferred.length(); i++) {
			string code = normalize_lang(preferred[i]);
			if (code != "" && available(code)) return code;
		}
		for (uint i = 0; i < preferred.length(); i++) {
			string code = normalize_lang(preferred[i]);
			if (code != "") return code;
		}
	}
	return normalize_lang(fallback);
}

// One call setup: loads the English base, then the requested language
// (or the OS language when lang is empty). Returns false when the requested
// catalog is missing and the base is used instead.
bool init(const string &in dir = "lang", const string &in lang = "") {
	path_prefix = dir;
	load_base("en");
	string target = normalize_lang(lang);
	if (target == "") target = detect("en");
	if (target == "" || target == "en") {
		if (base_catalog !is null) {
			@active_catalog = base_catalog;
			active_lang = "en";
			return true;
		}
		return false;
	}
	if (load(target)) return true;
	@active_catalog = base_catalog;
	active_lang = "en";
	return false;
}

bool set_language(const string &in lang) {
	string code = normalize_lang(lang);
	if (code == "en" && base_catalog !is null) {
		@active_catalog = base_catalog;
		active_lang = "en";
		return true;
	}
	return load(code);
}

string language() { return active_lang; }

// ---------------------------------------------------------------------------
// lookup and translation
// ---------------------------------------------------------------------------

void record_missing(const string &in id) {
	if (missing_seen.exists(id)) return;
	missing_seen.set(id, true);
	missing_list.insert_last(id);
}

bool lookup_in(dictionary@ d, const string &in key, string &result) {
	if (d is null) return false;
	return d.get(key, result);
}

// active idi -> active id.other -> base idi -> base id.other
bool lookup_plural(const string &in id, const string &in cat, string &result) {
	string key;
	if (lookup_in(active_catalog, id + "." + cat, result)) return true;
	if (cat != "other" && lookup_in(active_catalog, id + ".other", result)) return true;
	if (lookup_in(active_catalog, id, result)) return true;
	if (lookup_in(base_catalog, id + "." + cat, result)) return true;
	if (cat != "other" && lookup_in(base_catalog, id + ".other", result)) return true;
	if (lookup_in(base_catalog, id, result)) return true;
	return false;
}

string t_args(const string &in id, const string[] &in args) {
	string text;
	if (lookup_in(active_catalog, id, text)) return format_text(text, args);
	if (lookup_in(base_catalog, id, text)) return format_text(text, args);
	record_missing(id);
	return id;
}

// Plural-aware translation. {0} is always the number itself, the extra
// arguments start at {1}.
string tn_args(const string &in id, double n, const string[] &in args) {
	string text;
	string cat = plural_category(n, active_lang);
	string[] all;
	all.insert_last(num(n));
	for (uint i = 0; i < args.length(); i++) all.insert_last(args[i]);
	if (lookup_plural(id, cat, text)) return format_text(text, all);
	record_missing(id);
	return id;
}

// --- t: id + 0..6 string arguments ---

string t(const string &in id) {
	string[] a;
	return t_args(id, a);
}

string t(const string &in id, const string &in a0) {
	string[] a;
	a.insert_last(a0);
	return t_args(id, a);
}

string t(const string &in id, const string &in a0, const string &in a1) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	return t_args(id, a);
}

string t(const string &in id, const string &in a0, const string &in a1, const string &in a2) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	a.insert_last(a2);
	return t_args(id, a);
}

string t(const string &in id, const string &in a0, const string &in a1, const string &in a2, const string &in a3) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	a.insert_last(a2);
	a.insert_last(a3);
	return t_args(id, a);
}

string t(const string &in id, const string &in a0, const string &in a1, const string &in a2, const string &in a3, const string &in a4) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	a.insert_last(a2);
	a.insert_last(a3);
	a.insert_last(a4);
	return t_args(id, a);
}

string t(const string &in id, const string &in a0, const string &in a1, const string &in a2, const string &in a3, const string &in a4, const string &in a5) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	a.insert_last(a2);
	a.insert_last(a3);
	a.insert_last(a4);
	a.insert_last(a5);
	return t_args(id, a);
}

// --- tn: id + number + 0..5 extra arguments ---

string tn(const string &in id, double n) {
	string[] a;
	return tn_args(id, n, a);
}

string tn(const string &in id, double n, const string &in a0) {
	string[] a;
	a.insert_last(a0);
	return tn_args(id, n, a);
}

string tn(const string &in id, double n, const string &in a0, const string &in a1) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	return tn_args(id, n, a);
}

string tn(const string &in id, double n, const string &in a0, const string &in a1, const string &in a2) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	a.insert_last(a2);
	return tn_args(id, n, a);
}

string tn(const string &in id, double n, const string &in a0, const string &in a1, const string &in a2, const string &in a3) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	a.insert_last(a2);
	a.insert_last(a3);
	return tn_args(id, n, a);
}

string tn(const string &in id, double n, const string &in a0, const string &in a1, const string &in a2, const string &in a3, const string &in a4) {
	string[] a;
	a.insert_last(a0);
	a.insert_last(a1);
	a.insert_last(a2);
	a.insert_last(a3);
	a.insert_last(a4);
	return tn_args(id, n, a);
}

// ---------------------------------------------------------------------------
// diagnostics
// ---------------------------------------------------------------------------

string[]@ missing_ids() { return missing_list; }
uint missing_count() { return missing_list.length(); }

void clear_missing() {
	missing_list.resize(0);
	missing_seen.delete_all();
}

string[]@ parse_errors() { return error_list; }
int parse_error_count() { return error_total; }

void clear_parse_errors() {
	error_list.resize(0);
	error_total = 0;
}

bool has(const string &in id) {
	string tmp;
	if (lookup_in(active_catalog, id, tmp)) return true;
	return lookup_in(base_catalog, id, tmp);
}

} // namespace loc
