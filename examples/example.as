/*
    nvlocale example.

    Run from the repository root:

        nvgt examples/example.as

    NVGT has no console output in script mode, so the result is written to
    examples/output.txt. In a real game replace `say()` with
    screen_reader_speak() or whatever speech function you use.
*/

#include "../nvlocale.as"

string log_text;
string dir = "../catalogs";  // NVGT runs the script with its own folder as CWD

void say(const string &in text) {
	log_text += text + "\n";
}

void main() {
	// Pick up the OS language when available, fall back to English.
	if (!loc::init(dir, "ru")) {
		say(loc::t("error.missing_catalog", "ru"));
	}
	say("language: " + loc::language());

	// A whole sentence is one ID: the translator controls word order.
	say(loc::t("menu.start"));
	say(loc::t("ui.volume", "7"));
	say(loc::t("msg.picked_up", "Мила", loc::t("item.whistle")));

	// Numbers: the decimal separator follows the active language.
	say(loc::num(7.5));
	say(loc::num(7.256, 1));

	// Plurals: tn() picks .one/.few/.many/.other by CLDR rules.
	say(loc::tn("bag.items", 1));
	say(loc::tn("bag.items", 2));
	say(loc::tn("bag.items", 5));
	say(loc::tn("bag.items", 1.5));

	// Extra arguments after the number start at {1}.
	say(loc::tn("talents.points", 28, "Village life, More to do, Talents"));

	// Switch language at runtime.
	loc::set_language("en");
	say(loc::tn("bag.items", 5));

	// Missing IDs are returned as-is and remembered for diagnostics.
	loc::clear_missing();
	say(loc::t("no.such.id"));
	say("missing: " + loc::missing_count());

	file_put_contents("output.txt", log_text);
}
