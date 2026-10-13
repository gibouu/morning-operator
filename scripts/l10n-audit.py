#!/usr/bin/env python3
"""Localization audit for MORE.

Lists string literals in Sources/ that look user-visible but were not extracted
into a string catalog by the compiler, and catalog keys missing a French value.

Usage:
  scripts/l10n-audit.py literals [DERIVED_DATA] [--file PATH]
  scripts/l10n-audit.py keys [DERIVED_DATA]          # extracted keys per catalog
  scripts/l10n-audit.py missing                      # catalog keys without French

Build first with SWIFT_EMIT_LOC_STRINGS=YES so .stringsdata files exist.
"""
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGS = {
    "MorningOperator": "Resources/Localizable.xcstrings",
    "MorningActivityWidget": "Sources/MorningActivityWidget/Localizable.xcstrings",
    "MorningCore": "Sources/MorningCore/Resources/Localizable.xcstrings",
    "MorningApple": "Sources/MorningApple/Resources/Localizable.xcstrings",
}


def target_for(path):
    rel = os.path.relpath(path, ROOT)
    parts = rel.split(os.sep)
    return parts[1] if len(parts) > 2 and parts[0] == "Sources" else None


def swift_literals(text):
    """Yields (line, column, body) for top-level string literals, skipping comments."""
    i, line, col, n = 0, 1, 1, len(text)

    def advance(k):
        nonlocal i, line, col
        for _ in range(k):
            if i < n and text[i] == "\n":
                line += 1
                col = 1
            else:
                col += 1
            i += 1

    def read_string():
        # Assumes text[i] starts a literal; returns body (with interpolations kept raw).
        start = i
        hashes = 0
        while text[i] == "#":
            hashes += 1
            advance(1)
        multi = text.startswith('"""', i)
        quote = '"""' if multi else '"'
        advance(len(quote))
        terminator = quote + "#" * hashes
        body_start = i
        while i < n:
            if text.startswith(terminator, i):
                body = text[body_start:i]
                advance(len(terminator))
                return body
            if text[i] == "\\" and text.startswith("#" * hashes, i + 1):
                if text.startswith("(", i + 1 + hashes):
                    advance(2 + hashes)
                    depth = 1
                    while i < n and depth:
                        c = text[i]
                        if c == '"' or (c == "#" and text.startswith('"', i + 1)):
                            read_string()
                            continue
                        if c == "(":
                            depth += 1
                        elif c == ")":
                            depth -= 1
                        advance(1)
                    continue
                advance(2)
                continue
            if not multi and text[i] == "\n":
                break
            advance(1)
        return text[body_start:i]

    while i < n:
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                advance(1)
        elif text.startswith("/*", i):
            depth = 0
            while i < n:
                if text.startswith("/*", i):
                    depth += 1
                    advance(2)
                elif text.startswith("*/", i):
                    depth -= 1
                    advance(2)
                    if depth == 0:
                        break
                else:
                    advance(1)
        elif text[i] == '"' or (text[i] == "#" and re.match(r'#+"', text[i:i + 8])):
            l, c = line, col
            yield l, c, read_string()
        else:
            advance(1)


def extracted(derived):
    by_file = defaultdict(list)
    for dirpath, _, files in os.walk(derived):
        for f in files:
            if not f.endswith(".stringsdata"):
                continue
            try:
                data = json.load(open(os.path.join(dirpath, f)))
            except Exception:
                continue
            src = data.get("source")
            for table, entries in data.get("tables", {}).items():
                for e in entries:
                    by_file[src].append((e.get("location", {}).get("startingLine", 0), e["key"], table))
    return by_file


USER_TEXT = re.compile(r"[A-Za-z]{2,}")


def looks_visible(body):
    plain = re.sub(r"\\\([^)]*\)", "", body)
    if not USER_TEXT.search(plain):
        return False
    # An interpolated value followed by words ("\\(count) saved") is a sentence.
    if "\\(" in body and re.search(r"[A-Za-z]{3,}", plain):
        return True
    if " " not in plain.strip():
        # Single tokens: keep capitalized words like "Calendar", skip identifiers/symbols.
        if re.fullmatch(r"[A-Z][a-z]+[.…!?]?", plain.strip()):
            return True
        return False
    if re.fullmatch(r"[a-z0-9_.\-]+(\s[a-z0-9_.\-]+)*", plain) and "." in plain:
        return False
    return True


def cmd_literals(derived, only=None):
    ext = extracted(derived)
    total = 0
    for dirpath, _, files in os.walk(os.path.join(ROOT, "Sources")):
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            path = os.path.join(dirpath, f)
            if only and os.path.abspath(only) != path:
                continue
            keys_by_line = defaultdict(list)
            for l, key, _ in ext.get(path, []):
                keys_by_line[l].append(key)
            src_lines = open(path).read().split("\n")
            hits = []
            for l, c, body in swift_literals(open(path).read()):
                if not looks_visible(body):
                    continue
                if l in keys_by_line:
                    # A line can mix a localized string with a plain one; the
                    # literal is covered only if its text appears in a key there.
                    parts = [p for p in re.split(r"\\\([^)]*\)", body) if p.strip()]
                    if any(all(p in key for p in parts) for key in keys_by_line[l]):
                        continue
                code = src_lines[l - 1]
                if "localized:" in code or "verbatim:" in code or "Logger" in code or "log." in code:
                    continue
                hits.append((l, body))
            if hits:
                print(f"\n## {os.path.relpath(path, ROOT)} ({len(hits)})")
                for l, body in hits:
                    print(f"{l}: {body[:160]}")
                total += len(hits)
    print(f"\n{total} candidate literals")


def cmd_keys(derived):
    ext = extracted(derived)
    keys = defaultdict(set)
    for path, entries in ext.items():
        t = target_for(path)
        for _, key, table in entries:
            keys[(t, table)].add(key)
    for (t, table), ks in sorted(keys.items(), key=lambda x: (str(x[0][0]), x[0][1])):
        print(f"{t} {table}: {len(ks)}")
    return keys


def cmd_missing():
    missing = 0
    for target, rel in CATALOGS.items():
        cat = json.load(open(os.path.join(ROOT, rel)))
        for key, entry in cat["strings"].items():
            if not key.strip() or entry.get("shouldTranslate") is False:
                continue
            fr = entry.get("localizations", {}).get("fr")
            if not fr:
                print(f"{target}: {key}")
                missing += 1
    print(f"{missing} keys without French")
    return missing


if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args[0] if args else "literals"
    derived = args[1] if len(args) > 1 and not args[1].startswith("--") else os.path.join(ROOT, ".build-xcode")
    only = args[args.index("--file") + 1] if "--file" in args else None
    if cmd == "literals":
        cmd_literals(derived, only)
    elif cmd == "keys":
        cmd_keys(derived)
    elif cmd == "missing":
        sys.exit(1 if cmd_missing() else 0)
