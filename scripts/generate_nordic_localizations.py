#!/usr/bin/env python3
"""Generate da/nb/fi/is Localizable.strings from en.lproj with full key coverage."""

import re
import sys
import time
from pathlib import Path

from deep_translator import GoogleTranslator

ROOT = Path(__file__).resolve().parents[1] / "SpectRoom"
EN = ROOT / "en.lproj" / "Localizable.strings"

# Apple .lproj code -> Google Translate target
LANGS = {
    "nb": ("no", "Norwegian"),
    "fi": ("fi", "Finnish"),
    "is": ("is", "Icelandic"),
}

ENTRY_RE = re.compile(r'^(\s*)"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:\.\d+)?[@sdf]|\\n|\\\"|\\\\")


def log(msg: str) -> None:
    print(msg, flush=True)


def protect(s: str):
    tokens = []

    def repl(m):
        tokens.append(m.group(0))
        return f"⟦P{len(tokens) - 1}⟧"

    return PLACEHOLDER_RE.sub(repl, s), tokens


def unprotect(s: str, tokens):
    out = s
    for i, tok in enumerate(tokens):
        for variant in (f"⟦P{i}⟧", f"[[P{i}]]", f"[P{i}]"):
            if variant in out:
                out = out.replace(variant, tok)
                break
    return out


def parse_lines(text: str):
    lines = text.splitlines(keepends=True)
    entries = []
    for i, line in enumerate(lines):
        m = ENTRY_RE.match(line.rstrip("\n"))
        if not m:
            continue
        indent, key, value = m.group(1), m.group(2), m.group(3)
        display = value.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
        entries.append((i, indent, key, value, display))
    return lines, entries


def escape_for_strings(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def translate_unique(values, google_target: str):
    unique = list(dict.fromkeys(values))
    cache = {}
    translator = GoogleTranslator(source="en", target=google_target)
    skip = {"SpectRoom", "OK", "SMS", "2FA", "MFA", ""}

    for idx, text in enumerate(unique, 1):
        if text.strip() in skip or text in skip:
            cache[text] = text
            continue
        protected, tokens = protect(text)
        try:
            tr = translator.translate(protected) or protected
        except Exception as exc:
            log(f"  retry ({exc})")
            time.sleep(1.2)
            try:
                tr = translator.translate(protected) or protected
            except Exception as exc2:
                log(f"  fail keep EN: {exc2} | {text[:50]}")
                tr = protected
        cache[text] = unprotect(tr, tokens)
        if idx % 25 == 0 or idx == len(unique):
            log(f"  unique {idx}/{len(unique)}")
        time.sleep(0.04)
    return [cache[v] for v in values]


def write_lang(apple_code: str, google_target: str, lang_name: str, lines, entries):
    log(f"\n=== {lang_name} ({apple_code}) ===")
    displays = [e[4] for e in entries]
    translated = translate_unique(displays, google_target)

    new_lines = list(lines)
    for i, line in enumerate(new_lines[:10]):
        if "Localizable.strings (English)" in line:
            new_lines[i] = line.replace("English", lang_name)

    for (line_idx, indent, key, _old, display), new_val in zip(entries, translated):
        if display.strip() == "SpectRoom":
            new_val = "SpectRoom"
        esc = escape_for_strings(new_val)
        new_lines[line_idx] = f'{indent}"{key}" = "{esc}";\n'

    out_dir = ROOT / f"{apple_code}.lproj"
    out_dir.mkdir(exist_ok=True)
    out_path = out_dir / "Localizable.strings"
    out_path.write_text("".join(new_lines), encoding="utf-8")

    _, out_entries = parse_lines(out_path.read_text(encoding="utf-8"))
    log(f"Wrote {out_path} ({len(out_entries)} keys)")
    if len(out_entries) != len(entries):
        log("WARNING: key count mismatch")
        sys.exit(1)


def main():
    text = EN.read_text(encoding="utf-8")
    lines, entries = parse_lines(text)
    log(f"Parsed {len(entries)} English keys")
    for apple_code, (google_target, lang_name) in LANGS.items():
        write_lang(apple_code, google_target, lang_name, lines, entries)
    log("\nDone.")


if __name__ == "__main__":
    main()
