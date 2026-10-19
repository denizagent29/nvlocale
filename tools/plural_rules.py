#!/usr/bin/env python3
"""Reference implementation of the CLDR plural rules used by nvlocale.nvgt.

This file is the source of truth for tests and for the linter: the
AngelScript table in nvlocale.nvgt must agree with it. Keep the two in sync
when a rule changes.
"""

from __future__ import annotations

import math

R_OTHER_ONLY = 0
R_ONE = 1
R_FR = 2
R_RU = 3
R_PL = 4
R_CS = 5
R_SL = 6
R_LT = 7
R_LV = 8
R_GA = 9
R_RO = 10
R_AR = 11
R_HE = 12
R_IS = 13
R_MK = 14
R_MT = 15
R_CY = 16
R_BR = 17
R_FA = 18
R_HI = 19
R_BG = 20
R_SR = 21
R_DA = 22

RULE_BY_LANG = {
    # no grammatical number at all
    **{l: R_OTHER_ONLY for l in
       ("ja", "zh", "ko", "th", "vi", "id", "ms", "lo", "my", "km", "jv", "su", "yue")},
    **{l: R_FR for l in ("fr", "pt", "hy")},
    **{l: R_RU for l in ("ru", "uk", "be")},
    "bg": R_BG,
    **{l: R_SR for l in ("sr", "hr", "bs")},
    "pl": R_PL,
    **{l: R_CS for l in ("cs", "sk")},
    "sl": R_SL,
    "lt": R_LT,
    "lv": R_LV,
    "ga": R_GA,
    "ro": R_RO,
    "ar": R_AR,
    **{l: R_HE for l in ("he", "iw")},
    "is": R_IS,
    "mk": R_MK,
    "mt": R_MT,
    "cy": R_CY,
    "br": R_BR,
    "fa": R_FA,
    **{l: R_HI for l in ("hi", "bn")},
    "da": R_DA,
}


def normalize_lang(code: str) -> str:
    code = (code or "").strip().lower().replace("_", "-").replace(".", "-")
    return code.split("-", 1)[0]


def rule_for(lang: str) -> int:
    return RULE_BY_LANG.get(normalize_lang(lang), R_ONE)


def category(n: float, lang: str) -> str:
    """Return zero/one/two/few/many/other for n in lang."""
    an = abs(float(n))
    if an > 9.0e18:
        return "other"
    frac = an != math.floor(an)
    i = int(math.floor(an))
    i10 = i % 10
    i100 = i % 100
    rule = rule_for(lang)

    if rule == R_OTHER_ONLY:
        return "other"
    if rule == R_ONE:
        return "one" if an == 1 else "other"
    if rule == R_DA:
        # CLDR da: n = 1 or t != 0, i.e. any fraction is "one".
        return "one" if (an == 1 or frac) else "other"
    if rule == R_FR:
        # CLDR: i = 0,1 — the fraction does not matter (1.5 is "one").
        return "one" if i in (0, 1) else "other"
    if rule == R_RU:
        if frac:
            return "other"
        if i10 == 1 and i100 != 11:
            return "one"
        if 2 <= i10 <= 4 and not 12 <= i100 <= 14:
            return "few"
        return "many"
    if rule == R_PL:
        if frac:
            return "other"
        if i == 1:
            return "one"
        if 2 <= i10 <= 4 and not 12 <= i100 <= 14:
            return "few"
        return "many"
    if rule == R_CS:
        if frac:
            return "many"
        if i == 1:
            return "one"
        if 2 <= i <= 4:
            return "few"
        return "other"
    if rule == R_SL:
        if frac:
            return "few"
        if i100 == 1:
            return "one"
        if i100 == 2:
            return "two"
        if i100 in (3, 4):
            return "few"
        return "other"
    if rule == R_LT:
        if frac:
            return "many"
        if i10 == 1 and not 11 <= i100 <= 19:
            return "one"
        if 2 <= i10 <= 9 and not 11 <= i100 <= 19:
            return "few"
        return "other"
    if rule == R_LV:
        if frac:
            return "other"
        if i10 == 0 or 11 <= i100 <= 19:
            return "zero"
        if i10 == 1 and i100 != 11:
            return "one"
        return "other"
    if rule == R_GA:
        if frac:
            return "other"
        if i == 1:
            return "one"
        if i == 2:
            return "two"
        if 3 <= i <= 6:
            return "few"
        if 7 <= i <= 10:
            return "many"
        return "other"
    if rule == R_RO:
        if frac:
            return "few"
        if i == 1:
            return "one"
        if i == 0 or 2 <= i100 <= 19:
            return "few"
        return "other"
    if rule == R_AR:
        if frac:
            return "other"
        if i == 0:
            return "zero"
        if i == 1:
            return "one"
        if i == 2:
            return "two"
        if 3 <= i100 <= 10:
            return "few"
        if 11 <= i100 <= 99:
            return "many"
        return "other"
    if rule == R_HE:
        if frac:
            return "other"
        if i == 1:
            return "one"
        if i == 2:
            return "two"
        if i != 0 and i10 == 0:
            return "many"
        return "other"
    if rule == R_IS:
        if frac:
            return "one"
        if i10 == 1 and i100 != 11:
            return "one"
        return "other"
    if rule == R_BG:
        if frac:
            return "other"
        if i10 == 1 and i100 != 11:
            return "one"
        return "other"
    if rule == R_SR:
        # CLDR also distinguishes fractional forms via the f operand;
        # a double does not know its visible fraction digits, so any
        # non-integer is treated as "other" here (documented limitation).
        if frac:
            return "other"
        if i10 == 1 and i100 != 11:
            return "one"
        if 2 <= i10 <= 4 and not 12 <= i100 <= 14:
            return "few"
        return "other"
    if rule == R_MK:
        if frac:
            return "other"
        if i10 == 1 and i100 != 11:
            return "one"
        return "other"
    if rule == R_MT:
        if frac:
            return "other"
        if i == 1:
            return "one"
        if i == 0 or 2 <= i100 <= 10:
            return "few"
        if 11 <= i100 <= 19:
            return "many"
        return "other"
    if rule == R_CY:
        if frac:
            return "other"
        if i == 0:
            return "zero"
        if i == 1:
            return "one"
        if i == 2:
            return "two"
        if i == 3:
            return "few"
        if i == 6:
            return "many"
        return "other"
    if rule == R_BR:
        if frac:
            return "other"
        if i10 == 1 and i100 not in (11, 71, 91):
            return "one"
        if i10 == 2 and i100 not in (12, 72, 92):
            return "two"
        if (i10 in (3, 4, 9)
                and not 10 <= i100 <= 19
                and not 70 <= i100 <= 79
                and not 90 <= i100 <= 99):
            return "few"
        if i != 0 and i % 1000000 == 0:
            return "many"
        return "other"
    if rule in (R_FA, R_HI):
        if i == 0 or an == 1:
            return "one"
        return "other"
    return "other"


def live_categories(lang: str, upto: int = 400) -> set[str]:
    """Categories that actually occur for this language.

    Integers 0..upto plus a few fractional samples. Used by the linter to
    know which .one/.few/.many variants a catalog is expected to contain.
    """
    seen = {category(float(n), lang) for n in range(0, upto + 1)}
    seen |= {category(x, lang) for x in (0.5, 1.5, 2.5, 10.5, 21.5)}
    return seen
