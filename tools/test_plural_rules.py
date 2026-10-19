#!/usr/bin/env python3
"""CLDR vectors for the nvlocale plural table.

Run: python3 tools/test_plural_rules.py
Any mismatch is printed and the process exits with 1.
"""

from plural_rules import category

VECTORS = [
    # English / German / Spanish / Italian: one only for exactly 1
    ("en", 0, "other"), ("en", 1, "one"), ("en", 2, "other"), ("en", 1.5, "other"),
    ("de", 1, "one"), ("de", 0, "other"),
    ("es", 1, "one"), ("it", 2, "other"),
    # French / Portuguese: one for integer part 0 or 1, fractions included
    ("fr", 0, "one"), ("fr", 1, "one"), ("fr", 1.5, "one"),
    ("fr", 0.5, "one"), ("fr", 2, "other"),
    ("pt", 0, "one"), ("pt", 1, "one"), ("pt", 2, "other"),
    # Russian family
    ("ru", 1, "one"), ("ru", 2, "few"), ("ru", 4, "few"), ("ru", 5, "many"),
    ("ru", 0, "many"), ("ru", 11, "many"), ("ru", 12, "many"),
    ("ru", 21, "one"), ("ru", 22, "few"), ("ru", 25, "many"),
    ("ru", 101, "one"), ("ru", 111, "many"), ("ru", 1.5, "other"),
    ("uk", 1, "one"), ("uk", 3, "few"), ("uk", 7, "many"),
    ("be", 2, "few"),
    # Bulgarian: only one/other, 11 is the exception
    ("bg", 1, "one"), ("bg", 21, "one"), ("bg", 11, "other"),
    ("bg", 5, "other"), ("bg", 2, "other"),
    # Serbian / Croatian / Bosnian: one/few/other, no "many"
    ("sr", 21, "one"), ("sr", 22, "few"), ("sr", 5, "other"),
    ("sr", 11, "other"), ("hr", 3, "few"), ("hr", 5, "other"),
    ("bs", 11, "other"), ("bs", 24, "few"),
    # Polish: 1 one; 2..4 few; everything else many
    ("pl", 1, "one"), ("pl", 2, "few"), ("pl", 4, "few"),
    ("pl", 5, "many"), ("pl", 12, "many"), ("pl", 22, "few"),
    ("pl", 25, "many"), ("pl", 0, "many"), ("pl", 1.5, "other"),
    # Czech / Slovak
    ("cs", 1, "one"), ("cs", 2, "few"), ("cs", 4, "few"),
    ("cs", 5, "other"), ("cs", 0, "other"), ("cs", 1.5, "many"),
    ("sk", 1, "one"), ("sk", 3, "few"), ("sk", 10, "other"), ("sk", 1.5, "many"),
    # Slovenian
    ("sl", 1, "one"), ("sl", 2, "two"), ("sl", 3, "few"), ("sl", 4, "few"),
    ("sl", 5, "other"), ("sl", 101, "one"), ("sl", 102, "two"),
    ("sl", 103, "few"), ("sl", 0, "other"), ("sl", 1.5, "few"),
    # Lithuanian
    ("lt", 1, "one"), ("lt", 2, "few"), ("lt", 9, "few"),
    ("lt", 10, "other"), ("lt", 11, "other"), ("lt", 21, "one"),
    ("lt", 22, "few"), ("lt", 1.5, "many"),
    # Latvian
    ("lv", 0, "zero"), ("lv", 10, "zero"), ("lv", 11, "zero"), ("lv", 19, "zero"),
    ("lv", 1, "one"), ("lv", 21, "one"), ("lv", 2, "other"), ("lv", 1.5, "other"),
    # Irish
    ("ga", 1, "one"), ("ga", 2, "two"), ("ga", 3, "few"), ("ga", 6, "few"),
    ("ga", 7, "many"), ("ga", 10, "many"), ("ga", 11, "other"),
    # Romanian
    ("ro", 1, "one"), ("ro", 0, "few"), ("ro", 2, "few"), ("ro", 19, "few"),
    ("ro", 20, "other"), ("ro", 101, "other"), ("ro", 1.5, "few"),
    # Arabic
    ("ar", 0, "zero"), ("ar", 1, "one"), ("ar", 2, "two"), ("ar", 3, "few"),
    ("ar", 10, "few"), ("ar", 11, "many"), ("ar", 99, "many"),
    ("ar", 100, "other"), ("ar", 102, "other"), ("ar", 1.5, "other"),
    # Hebrew
    ("he", 1, "one"), ("he", 2, "two"), ("he", 10, "many"),
    ("he", 20, "many"), ("he", 3, "other"), ("he", 1.5, "other"),
    # Icelandic
    ("is", 1, "one"), ("is", 21, "one"), ("is", 11, "other"),
    ("is", 2, "other"), ("is", 1.5, "one"),
    # Macedonian
    ("mk", 1, "one"), ("mk", 21, "one"), ("mk", 11, "other"), ("mk", 2, "other"),
    # Maltese
    ("mt", 1, "one"), ("mt", 0, "few"), ("mt", 2, "few"), ("mt", 10, "few"),
    ("mt", 11, "many"), ("mt", 19, "many"), ("mt", 20, "other"), ("mt", 100, "other"),
    # Welsh
    ("cy", 0, "zero"), ("cy", 1, "one"), ("cy", 2, "two"),
    ("cy", 3, "few"), ("cy", 6, "many"), ("cy", 4, "other"),
    # Breton
    ("br", 1, "one"), ("br", 2, "two"), ("br", 3, "few"),
    ("br", 10, "other"), ("br", 21, "one"), ("br", 22, "two"),
    ("br", 1000000, "many"),
    # Persian / Hindi
    ("fa", 0, "one"), ("fa", 1, "one"), ("fa", 2, "other"),
    ("hi", 0, "one"), ("hi", 1, "one"), ("hi", 2, "other"), ("hi", 1.5, "other"),
    # No grammatical number
    ("ja", 1, "other"), ("zh", 1, "other"), ("ko", 1, "other"),
    ("th", 1, "other"), ("vi", 1, "other"), ("id", 1, "other"), ("ms", 1, "other"),
    # Danish: any fraction is "one"
    ("da", 1, "one"), ("da", 1.5, "one"), ("da", 0.5, "one"),
    ("da", 0, "other"), ("da", 2, "other"),
    # Turkish is regular
    ("tr", 1, "one"), ("tr", 0, "other"), ("tr", 2, "other"),
    # Language tags and unknown languages
    ("ru-RU", 5, "many"), ("pt_BR", 0, "one"), ("xx", 1, "one"),
]


def main() -> int:
    bad = 0
    for lang, n, expected in VECTORS:
        got = category(n, lang)
        if got != expected:
            bad += 1
            print(f"FAIL {lang:6} {n:>8}: expected {expected}, got {got}")
    print(f"{len(VECTORS) - bad}/{len(VECTORS)} vectors passed")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
