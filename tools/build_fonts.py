#!/usr/bin/env python3
"""Regenerate the Noto fallback-font subsets from the locale catalogs (issue #5).

Non-Latin UI text (CJK / Devanagari / Arabic) renders via Noto fonts attached as
per-glyph fallbacks on the default font (see main.gd `_setup_font_fallbacks`).
Shipping the full Noto fonts would add ~10 MB (CJK alone); instead this subsets
each to ONLY the glyphs its catalog actually uses — a few KB each.

Re-run after editing any non-Latin catalog:

    python3 tools/build_fonts.py

Needs: fontTools (pip install fonttools) and network access to the Noto sources.
Writes assets/fonts/NotoSans{SC,Devanagari,Arabic}-subset.ttf.
"""
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (output filename, locale code, upstream url, is_variable, codepoint test)
FONTS = [
    ("NotoSansSC-subset.ttf", "zh_CN",
     "https://github.com/google/fonts/raw/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf",
     True, lambda c: ord(c) >= 0x2E80),
    ("NotoSansDevanagari-subset.ttf", "hi",
     "https://raw.githubusercontent.com/notofonts/notofonts.github.io/main/fonts/NotoSansDevanagari/unhinted/ttf/NotoSansDevanagari-Regular.ttf",
     False, lambda c: 0x0900 <= ord(c) <= 0x097F or 0xA8E0 <= ord(c) <= 0xA8FF),
    ("NotoSansArabic-subset.ttf", "ar",
     "https://raw.githubusercontent.com/notofonts/notofonts.github.io/main/fonts/NotoSansArabic/unhinted/ttf/NotoSansArabic-Regular.ttf",
     False, lambda c: (0x0600 <= ord(c) <= 0x06FF or 0x0750 <= ord(c) <= 0x077F
                       or 0xFB50 <= ord(c) <= 0xFEFF)),
]


def chars_in_po(path, test):
    out = set()
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r'msgstr "(.*)"$', line.rstrip("\n"))
            if m:
                out.update(ch for ch in m.group(1) if test(ch))
    return out


def main():
    fdir = os.path.join(ROOT, "assets", "fonts")
    for out, loc, url, variable, test in FONTS:
        po = os.path.join(ROOT, "locale", f"{loc}.po")
        chars = chars_in_po(po, test)
        if not chars:
            print(f"skip {out}: locale/{loc}.po not present (or no in-script glyphs yet)")
            continue
        with tempfile.TemporaryDirectory() as td:
            raw = os.path.join(td, "raw.ttf")
            print(f"fetch {url}")
            urllib.request.urlretrieve(url, raw)
            src = raw
            if variable:  # pin the weight axis so the subset is a static Regular
                src = os.path.join(td, "inst.ttf")
                subprocess.run([sys.executable, "-m", "fontTools.varLib.instancer",
                                raw, "wght=400", "-o", src], check=True,
                               stdout=subprocess.DEVNULL)
            txt = os.path.join(td, "chars.txt")
            with open(txt, "w", encoding="utf-8") as f:
                f.write("".join(sorted(chars)))
            dst = os.path.join(fdir, out)
            subprocess.run([sys.executable, "-m", "fontTools.subset", src,
                            f"--text-file={txt}", f"--output-file={dst}",
                            "--no-hinting", "--layout-features=*",
                            "--drop-tables+=DSIG"], check=True)
            print(f"wrote {out}: {len(chars)} glyphs, {os.path.getsize(dst)} bytes")


if __name__ == "__main__":
    main()
