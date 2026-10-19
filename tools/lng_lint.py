#!/usr/bin/env python3
"""Linter for nvlocale .lng catalogs.

Usage:
    python3 tools/lng_lint.py                    # every catalogs/*.lng vs en
    python3 tools/lng_lint.py catalogs/ru.lng    # only this one
    python3 tools/lng_lint.py --base catalogs/en.lng catalogs/ru.lng
    python3 tools/lng_lint.py --strict           # warnings also fail

Checks:
  * syntax: missing separator, empty id, whitespace in id, duplicate id
  * ids that are missing from a translation or unknown to the base
  * placeholders: a translation must not use {N} the caller does not pass
  * plural variants: categories the language actually uses must be present
  * categories the language never uses are reported as dead weight
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass, field

from plural_rules import live_categories, normalize_lang

CATEGORIES = ("zero", "one", "two", "few", "many", "other")
COMMENT_MARKS = ("#", ";")


@dataclass
class Entry:
    value: str
    line: int


@dataclass
class Catalog:
    path: str
    lang: str
    entries: dict[str, Entry] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def log_error(self, line: int | None, msg: str) -> None:
        self.errors.append(_format(self.path, line, msg))

    def log_warning(self, line: int | None, msg: str) -> None:
        self.warnings.append(_format(self.path, line, msg))


def _format(path: str, line: int | None, msg: str) -> str:
    if line is None:
        return f"{path}: {msg}"
    return f"{path}:{line}: {msg}"


def parse(path: str, lang: str) -> Catalog:
    cat = Catalog(path=path, lang=lang)
    with open(path, "r", encoding="utf-8-sig") as fh:
        lines = fh.read().split("\n")

    for lineno, raw in enumerate(lines, start=1):
        s = raw.strip()
        if not s:
            continue
        if s.startswith(COMMENT_MARKS) or s.startswith("//"):
            continue

        sep, width = s.find("[=]"), 3
        if sep < 0:
            sep, width = s.find("="), 1
        if sep < 0:
            cat.log_error(lineno, "missing separator ([=] or =)")
            continue

        key = s[:sep].strip()
        value = s[sep + width:].strip()

        if not key:
            cat.log_error(lineno, "empty id")
            continue
        if any(ch.isspace() for ch in key):
            cat.log_error(lineno, f"id contains whitespace: {key!r}")
            continue
        if key in cat.entries:
            cat.log_warning(
                lineno,
                f"duplicate id {key!r} (line {cat.entries[key].line} is overridden)",
            )
        cat.entries[key] = Entry(value=value, line=lineno)

    return cat


def split_plural(key: str) -> tuple[str, str | None]:
    """'bag.items.few' -> ('bag.items', 'few'); 'bag.items' -> ('bag.items', None)."""
    if "." not in key:
        return key, None
    head, _, tail = key.rpartition(".")
    if tail in CATEGORIES:
        return head, tail
    return key, None


def placeholders(text: str) -> tuple[set[int], list[str]]:
    """Indices used as {N}; also returns structural problems.

    Mirrors nvlocale.as: {{ and }} are literal braces, everything else that
    looks like {digits} is a placeholder, a stray brace is just text.
    """
    used: set[int] = set()
    problems: list[str] = []
    i, n = 0, len(text)
    while i < n:
        if text[i] == "{" and i + 1 < n and text[i + 1] == "{":
            i += 2
            continue
        if text[i] == "{" and i + 1 < n and text[i + 1].isdigit():
            j = i + 1
            while j < n and text[j].isdigit():
                j += 1
            if j < n and text[j] == "}":
                used.add(int(text[i + 1:j]))
                i = j + 1
                continue
            problems.append(f"unclosed placeholder {text[i:j]!r}")
        if text[i] == "}" and i + 1 < n and text[i + 1] == "}":
            i += 2
            continue
        i += 1
    return used, problems


def group(cat: Catalog) -> dict[str, dict[str | None, Entry]]:
    """Group entries by logical id: {'bag.items': {None|'one'|'few': Entry}}."""
    out: dict[str, dict[str | None, Entry]] = {}
    for key, entry in cat.entries.items():
        base, cat_name = split_plural(key)
        out.setdefault(base, {})[cat_name] = entry
    return out


def lint_target(base: Catalog, target: Catalog) -> None:
    base_ids = group(base)
    target_ids = group(target)
    lang_categories = live_categories(target.lang)

    for base_id, base_forms in base_ids.items():
        if base_id not in target_ids:
            target.log_warning(None, f"untranslated id {base_id!r}")
            continue

        forms = target_ids[base_id]
        known, problems = set(), []
        # placeholders the caller can supply come from the base entry
        base_known: set[int] = set()
        for entry in base_forms.values():
            idx, probs = placeholders(entry.value)
            base_known |= idx
            problems.extend(probs)
        for entry in forms.values():
            idx, probs = placeholders(entry.value)
            known |= idx
            problems.extend(probs)

        for problem in problems:
            target.log_error(next(iter(forms.values())).line, problem)

        extra = known - base_known
        if extra:
            target.log_error(
                next(iter(forms.values())).line,
                f"{base_id}: placeholder(s) {sorted(extra)} not supplied by the base "
                f"entry (base uses {sorted(base_known) or 'none'})",
            )
        dropped = base_known - known
        if dropped:
            target.log_warning(
                next(iter(forms.values())).line,
                f"{base_id}: placeholder(s) {sorted(dropped)} dropped in translation",
            )

        has_variants = any(name is not None for name in forms)
        if has_variants:
            present = {name for name in forms if name is not None}
            needed = lang_categories & set(CATEGORIES)
            missing = needed - present
            dead = present - needed
            line = next(iter(forms.values())).line
            if "other" not in present and None not in forms:
                target.log_error(line, f"{base_id}: plural entry has no .other variant")
            elif missing:
                target.log_warning(
                    line,
                    f"{base_id}: missing plural variant(s) {sorted(missing)} "
                    f"for '{target.lang}'",
                )
            if dead:
                target.log_warning(
                    line,
                    f"{base_id}: variant(s) {sorted(dead)} never occur in "
                    f"'{target.lang}'",
                )

    for target_id, forms in target_ids.items():
        if target_id not in base_ids:
            line = next(iter(forms.values())).line
            target.log_warning(line, f"id {target_id!r} has no base entry")


def main(argv: list[str]) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    default_catalogs = os.path.normpath(os.path.join(here, "..", "catalogs"))
    default_base = os.path.join(default_catalogs, "en.lng")

    ap = argparse.ArgumentParser(description="Lint nvlocale catalog files")
    ap.add_argument("files", nargs="*", help="target .lng files (default: all in catalogs/)")
    ap.add_argument("--base", default=default_base, help="base catalog (default: catalogs/en.lng)")
    ap.add_argument("--strict", action="store_true", help="treat warnings as failures")
    args = ap.parse_args(argv)

    base = parse(args.base, normalize_lang(os.path.basename(args.base).split(".")[0]))
    if args.files:
        targets = args.files
    else:
        targets = sorted(
            os.path.join(default_catalogs, name)
            for name in os.listdir(default_catalogs)
            if name.endswith(".lng")
        )

    all_errors = list(base.errors)
    all_warnings = list(base.warnings)

    for path in targets:
        lang = normalize_lang(os.path.basename(path).split(".")[0])
        if os.path.abspath(path) == os.path.abspath(args.base):
            continue
        target = parse(path, lang)
        lint_target(base, target)
        all_errors += target.errors
        all_warnings += target.warnings

    for line in all_errors:
        print(f"error: {line}")
    for line in all_warnings:
        print(f"warning: {line}")

    print(
        f"\n{len(all_errors)} error(s), {len(all_warnings)} warning(s), "
        f"{len(targets)} file(s) checked"
    )
    if all_errors:
        return 1
    if args.strict and all_warnings:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
