#!/usr/bin/env python3
"""Tests for the parts of `theme` that handle untrusted input.

Themes are downloaded from other people's repositories and their values end up
in files that get executed, so these are the checks that must never regress.

Run:  python3 tests/test_theme.py
"""

import subprocess
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
theme = SourceFileLoader("theme", str(ROOT / "bin" / "theme")).load_module()

failures = []


def check(name, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}{'' if ok else f'  — {detail}'}")
    if not ok:
        failures.append(name)


def write_theme(d, body):
    p = Path(d) / "colors.toml"
    p.write_text(body)
    return p


print("colour validation")
with tempfile.TemporaryDirectory() as d:
    # A shell payload smuggled through a colour must be refused outright.
    p = write_theme(d, 'background = "#1a1a1a"\nforeground = "#eeeeee"\n'
                       'accent = "#ff8800$(touch /tmp/omakase-pwned)"\n')
    r = subprocess.run([sys.executable, str(ROOT / "bin" / "theme"), "set", "x"],
                       capture_output=True, text=True)
    try:
        theme.load(p)
        check("rejects command substitution in a colour", False, "load() accepted it")
    except SystemExit as e:
        check("rejects command substitution in a colour", "not a hex colour" in str(e), str(e))

    p = write_theme(d, 'background = "#1a1a1a"\nforeground = "#eeeeee"\n'
                       'accent = "#ff8800`id`"\n')
    try:
        theme.load(p)
        check("rejects backticks in a colour", False)
    except SystemExit:
        check("rejects backticks in a colour", True)

    # Legitimate shapes still load, and normalise.
    p = write_theme(d, 'background = "#fff"\nforeground = "eeeeee"\n'
                       'accent = "#ff8800cc"\nname = "Fine $(id) `x` \\"q\\""\n'
                       'appearance = "neither"\n')
    c = theme.load(p)
    check("expands 3-digit hex", c["background"] == "#ffffff", c["background"])
    check("accepts hex without #", c["foreground"] == "#eeeeee", c["foreground"])
    check("drops the alpha channel", c["accent"] == "#ff8800", c["accent"])
    check("strips shell metacharacters from free text",
          not any(ch in c["name"] for ch in '$`"\\'), c["name"])
    check("falls back to a valid appearance", c["appearance"] in ("dark", "light"),
          c["appearance"])

print("generated files carry no executable payload")
with tempfile.TemporaryDirectory() as d:
    p = write_theme(d, 'background = "#1a1a1a"\nforeground = "#eeeeee"\naccent = "#ff8800"\n')
    c = theme.load(p)
    gen, borders = Path(d) / "gen", Path(d) / "bordersrc"
    gen.mkdir()
    theme.GEN, theme.SKETCHYBAR_COLORS = gen, gen / "sketchybar-colors.sh"
    theme.GHOSTTY_CONF, theme.BORDERS_RC = gen / "ghostty.conf", borders
    theme.gen_sketchybar(c)
    theme.gen_ghostty(c)
    body = theme.SKETCHYBAR_COLORS.read_text()
    exports = [l.split("=", 1)[1].strip("'") for l in body.splitlines()
               if l.startswith("export ")]
    check("every exported value is a plain hex literal",
          all(v.startswith("0x") and v[2:].isalnum() for v in exports),
          [v for v in exports if not (v.startswith("0x") and v[2:].isalnum())])
    check("ghostty palette holds hex only",
          all(ln.split("=")[-1].strip().lstrip("#").isalnum()
              for ln in theme.GHOSTTY_CONF.read_text().splitlines()
              if ln.startswith("palette")))

    # Belt and braces: even if validation were bypassed, the shell writer must
    # neutralise a payload rather than pass it through.
    check("sb() quotes a hostile value", theme.sb("#ff8800$(id)") == "'0xffff8800$(id)'",
          theme.sb("#ff8800$(id)"))

print("paths from a remote listing stay inside themes/")
with tempfile.TemporaryDirectory() as d:
    base = Path(d)
    (base / "ok").mkdir()
    for bad in ("../escape", "..", "/etc/passwd", ".hidden", "a/b"):
        try:
            theme.safe_child(base, bad)
            check(f"refuses {bad!r}", False, "accepted")
        except SystemExit:
            check(f"refuses {bad!r}", True)
    check("accepts a normal name", theme.safe_child(base, "ok").name == "ok")

print("applescript quoting")
check("escapes quotes in a path",
      theme.osa_str('a"b') == '"a\\"b"', theme.osa_str('a"b'))
check("escapes backslashes",
      theme.osa_str("a\\b") == '"a\\\\b"', theme.osa_str("a\\b"))

print()
if failures:
    print(f"{len(failures)} failing: {', '.join(failures)}")
    sys.exit(1)
print("all good")
