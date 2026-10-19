# nvlocale

ID-based localization for NVGT.

Not templates like `%1 has %2 %3`, but whole sentences: one phrase is one ID,
and the pieces are inserted as `{0}`, `{1}`. The translator sees the entire
sentence, so word order, cases and agreement stay in the translator's hands
instead of being glued together from independently translated fragments.

## What's inside

- `nvlocale.nvgt` — the library itself, one file, no dependencies.
- `catalogs/en.lng`, `catalogs/ru.lng` — example catalogs (base and Russian).
- `tools/plural_rules.py` — reference implementation of the plural rules in Python.
- `tools/test_plural_rules.py` — 176 CLDR vectors that check the rule table.
- `tools/lng_lint.py` — catalog linter: missing IDs, extra placeholders,
  missing plural forms.
- `tests/test.nvgt` — library tests running on the NVGT engine itself.
- `examples/example.nvgt` — a runnable example.

`.nvgt` is NVGT's native script extension; the language inside is AngelScript.
The library follows the same convention as the engine's own includes
(`menu.nvgt`, `form.nvgt`, …), so `#include "nvlocale.nvgt"` looks like any
other NVGT include.

## Quick start

```angelscript
#include "nvlocale.nvgt"
using loc;

void main() {
	init("catalogs", "ru");          // folder and language; "" means the system language
	screen_reader_speak(t("menu.start"));
	screen_reader_speak(t("ui.volume", "7"));
	screen_reader_speak(t("msg.picked_up", "Mila", t("item.whistle")));
	screen_reader_speak(tn("bag.items", 5));   // "Your bag has 5 items."
}
```

`init()` loads the English base catalog first, then the requested language.
If the language file is missing, English stays and the function returns `false`.

A note on paths: NVGT runs a script with the script's own folder as the current
directory. Paths to catalogs are therefore resolved relative to that folder,
not to the project root.

## The `.lng` format

UTF-8, line by line. Empty lines and lines starting with `#`, `;` or `//` are
skipped.

```
id[=]text with {0} and {1}
bag.items.one[=]Your bag has {0} item.
bag.items.other[=]Your bag has {0} items.
```

- The separator is `[=]` (as in Life in Nature language packs) or a plain `=`.
  If a line contains both, `[=]` wins because it is searched first.
- An ID may not contain spaces or tabs.
- Whitespace around the ID and the text is trimmed.
- A repeated definition overrides the previous one, so a second file can patch
  the base catalog.
- A BOM at the start of the file is stripped.

### Escaping and placeholders

Processing is a single pass, with no double unescaping:

| In the file | In the result |
|---|---|
| `\n`, `\t`, `\r` | newline, tab, carriage return |
| `\\` | one backslash |
| `{{` and `}}` | literal `{` and `}` |
| `{0}`, `{1}`, … | the argument with that number |
| `\q` (unknown escape) | the backslash is kept: `\q` |
| a lone `{` or `}` | stays as text |

`{{0}}` prints a literal `{0}` and does not substitute an argument.

## API

```angelscript
// Loading
bool init(const string &in dir = "lang", const string &in lang = "");
bool load(const string &in lang);                  // dir/<lang>.lng
bool load_file(const string &in lang, const string &in path);
bool load_base(const string &in lang = "en");      // base only
bool available(const string &in lang);
string detect(const string &in fallback = "en");   // OS language

// Language
bool set_language(const string &in lang);
string language();

// Translation
string t(id);                    // and overloads with 1..6 string arguments
string tn(id, double n);         // and overloads with 0..5 extra arguments
string t_args(id, const string[] &in args);
string tn_args(id, double n, const string[] &in args);

// Numbers
string num(double v, int precision = -1);
string plural_category(double n, const string &in lang = "");

// Diagnostics
bool has(const string &in id);
string[]@ missing_ids();
uint missing_count();
void clear_missing();
string[]@ parse_errors();
int parse_error_count();
void clear_parse_errors();
```

`tn()` inserts the number as the first argument — it is always `{0}`. Extra
arguments start at `{1}`. The number is formatted with the decimal separator
of the active language: `7.5` → `7.5` in English, `7,5` in Russian.

`num(v)` without a precision prints the shortest form (`7` → `"7"`, `7.5` →
`"7.5"`). With a precision, `num(7.256, 1)` rounds to `7.3`.

If an ID is not found, `t()` returns the ID itself and records it in
`missing_ids()`. That is handy both in development and in production: the
screen shows exactly which key is missing, and the list can be dumped at the
end of a session.

## Plurals

The rule table is not a DSL but a fixed set of 23 CLDR functions. They are
written once in the library and never shown to translators: a translator just
writes the `.one`, `.few`, `.many`, `.other` variants for their language.

Variant selection: `tn()` determines the CLDR category of the number for the
active language, then looks up `id.<category>`. The fallback chain is:

1. active language, `id.<category>`
2. active language, `id.other`
3. active language, `id`
4. base language, `id.<category>`
5. base language, `id.other`
6. base language, `id`
7. return the ID itself and record it as missing

Which categories a language needs:

- `other` — always required, the last line of defence.
- `one` / `other` — English, German, Spanish, Italian, Turkish and most
  "ordinary" languages.
- `one` / `few` / `many` / `other` — Russian, Ukrainian, Belarusian.
- `one` / `few` / `other` — Serbian, Croatian, Bosnian, Bulgarian,
  Macedonian (no `many`).
- `zero` / `one` / `two` / `few` / `many` / `other` — Arabic, Welsh; Latvian
  uses `zero`, Irish uses `one/two/few/many/other`.
- Only `other` — Japanese, Chinese, Korean, Thai, Vietnamese, Indonesian,
  Malay and other languages without grammatical number.

The full language table is `RULE_BY_LANG` in `nvlocale.nvgt` and in
`tools/plural_rules.py` (the two tables must match).

To add a language with a non-standard rule: write the rule function in
`plural_category()` and add an `R_*` constant, then add the language to
`language_rule()`. If the language fits an existing rule, one line in
`language_rule()` is enough.

## Linter

```sh
python3 tools/lng_lint.py                 # every catalogs/*.lng against en
python3 tools/lng_lint.py catalogs/ru.lng
python3 tools/lng_lint.py --strict        # warnings also fail
```

It checks:

- syntax: missing separator, empty ID, whitespace in an ID, duplicate ID;
- IDs that are untranslated or unknown to the base catalog;
- placeholders: a translation must not use `{N}` the caller does not pass;
  a dropped placeholder is a warning;
- plural forms: missing ones for the language are a warning, dead ones (the
  language never uses them) are also a warning;
- a plural entry without `.other` is an error.

## Tests

```sh
python3 tools/test_plural_rules.py       # 176 CLDR vectors
nvgt tests/test.nvgt                     # 42 checks on the engine
nvgt examples/example.nvgt               # example, result in examples/output.txt
```

NVGT writes nothing to the console in script mode, so `tests/test.nvgt`
writes its report to `tests/last_run.log` (the last line is `RESULT: PASS` or
`RESULT: FAIL`), and the example writes to `examples/output.txt`.

Verified on NVGT 0.90.0-dev, Linux x86_64 (native) and arm64 (via qemu):
42/42 engine checks, 176/176 CLDR vectors, lint clean in strict mode.

## Known limitations

- Serbian, Croatian and Bosnian distinguish fractional forms by the number of
  visible fraction digits (`f`). A `double` does not carry that, so any
  non-integer is treated as `other`. For integers the rules are exact.
- `pt-PT` and `pt-BR` are collapsed into a single `pt`; regional plural
  differences are practically nonexistent for indie games.
- Without a precision, `num()` returns what `string(double)` prints; for very
  large numbers that may be exponent notation.
- The decimal separator is localized, the thousands separator is not.
- In NVGT `out` is a reserved word, so variable names in the library and the
  examples account for that.

## License

MIT, see `LICENSE`.
