#!/usr/bin/env python3
"""Type a chat line / slash command into the running game window via X11 (XTEST).
Usage: say.py "/diplo info"    (needs: pip install python-xlib, wmctrl)"""
import subprocess, sys, time
from Xlib import X, XK, display
from Xlib.ext import xtest

TITLE = "Diplomacy Mod"
d = display.Display()

def press(keysym_name_or_char, shift=False):
    ks = XK.string_to_keysym(keysym_name_or_char)
    kc = d.keysym_to_keycode(ks)
    if not kc:
        raise SystemExit(f"no keycode for {keysym_name_or_char!r}")
    # shift needed if the keysym lives on the shifted level of its keycode
    shift = shift or d.keycode_to_keysym(kc, 0) != ks
    sk = d.keysym_to_keycode(XK.XK_Shift_L)
    if shift: xtest.fake_input(d, X.KeyPress, sk)
    xtest.fake_input(d, X.KeyPress, kc); xtest.fake_input(d, X.KeyRelease, kc)
    if shift: xtest.fake_input(d, X.KeyRelease, sk)
    d.sync(); time.sleep(0.02)

NAMES = {" ": "space", "/": "slash", "_": "underscore", "-": "minus", ".": "period",
         ",": "comma", ":": "colon", "!": "exclam", "'": "apostrophe", '"': "quotedbl"}

def main():
    text = " ".join(sys.argv[1:])
    if not text: raise SystemExit(__doc__)
    if subprocess.run(["wmctrl", "-a", TITLE]).returncode != 0:
        raise SystemExit("game window not found (is it running?)")
    time.sleep(0.3)
    press("Return")          # open chat
    time.sleep(0.1)
    for ch in text:
        press(NAMES.get(ch, ch))
    press("Return")          # send
main()
