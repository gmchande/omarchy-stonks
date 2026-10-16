#!/usr/bin/env python3
"""Pointer gestures and modified keys for test/tophat.sh, each on one Wayland
connection to the nested session.

wayland.py beside this file is agentdesk/wayland.py from
https://github.com/enricofranke/omarchy-computer-use at commit
a1de2c2a8ae01bc5024f93a09c10752c3e4c4be0, unmodified; LICENSE is that
repository's. This adds a virtual keyboard with a US keymap, so a modifier is
held from before a press until after its release, and a shifted letter reaches
Qt as its text ("J") and as Shift+Key_J at once, which wtype cannot do.

Usage: drive.py SOCKET WIDTH HEIGHT COMMAND ARGS...
  move X Y
  click X Y BUTTON MODS        BUTTON is left, right, or middle
  drag X1 Y1 X2 Y2
  scroll X Y NOTCHES MODS      whole wheel notches; positive scrolls down
  key MODS KEY                 KEY is a letter, a digit, or a name in NAMED
MODS is a comma list of shift, ctrl, alt, super, or "-" for none. SOCKET is an
absolute path: nothing is read from the environment.
"""

import os
import socket
import struct
import sys
import time

from wayland import AXIS_VERTICAL, BUTTONS, VirtualPointer, _now_ms, _uint

# The real modifiers of the keymap below.
MODS = {"shift": 0x1, "ctrl": 0x4, "alt": 0x8, "super": 0x40}
# evdev key codes, as zwp_virtual_keyboard_v1.key takes them.
KEYS = {c: 16 + i for i, c in enumerate("qwertyuiop")}
KEYS |= {c: 30 + i for i, c in enumerate("asdfghjkl")}
KEYS |= {c: 44 + i for i, c in enumerate("zxcvbnm")}
KEYS |= {str((i + 1) % 10): 2 + i for i in range(10)}
NAMED = {"Escape": 1, "BackSpace": 14, "Tab": 15, "Return": 28, "space": 57,
         "Up": 103, "Left": 105, "Right": 106, "Down": 108, "Delete": 111}
KEYMAP = b"""xkb_keymap {
  xkb_keycodes { include "evdev+aliases(qwerty)" };
  xkb_types { include "complete" };
  xkb_compat { include "complete" };
  xkb_symbols { include "pc+us+inet(evdev)" };
};
\0"""


class Keyboard:
    """A virtual keyboard on an existing connection."""

    def __init__(self, conn):
        self.conn = conn
        seat = conn.bind("wl_seat", 1)
        manager = conn.bind("zwp_virtual_keyboard_manager_v1", 1)
        self.obj = conn._new_id()
        conn.send(manager, 0, _uint(seat, self.obj))
        fd = os.memfd_create("tophat-keymap")
        try:
            os.write(fd, KEYMAP)
            payload = _uint(1, len(KEYMAP))  # format xkb_v1; the fd rides beside
            header = struct.pack("<II", self.obj, (8 + len(payload)) << 16)
            socket.send_fds(conn.sock, [header + payload], [fd])
        finally:
            os.close(fd)
        conn.roundtrip()

    def modifiers(self, mask):
        self.conn.send(self.obj, 2, _uint(mask, 0, 0, 0))
        self.conn.roundtrip()

    def key(self, code, pressed):
        self.conn.send(self.obj, 1, _uint(_now_ms(), code, 1 if pressed else 0))
        self.conn.roundtrip()

    def close(self):
        self.conn.send(self.obj, 3)
        self.conn.roundtrip()


def mask_of(mods):
    if mods == "-":
        return 0
    mask = 0
    for name in mods.split(","):
        if name not in MODS:
            raise SystemExit(f"drive.py: unknown modifier {name!r}")
        mask |= MODS[name]
    return mask


def code_of(key):
    code = KEYS.get(key, NAMED.get(key))
    if code is None:
        raise SystemExit(f"drive.py: no key code for {key!r}")
    return code


def main(argv):
    socket_path, width, height, command, *args = argv
    if not socket_path.startswith("/"):
        raise SystemExit("drive.py: SOCKET must be an absolute path")
    pointer = VirtualPointer(socket_path, int(width), int(height))
    keyboard = None
    held_button = None
    held_key = None
    mask = 0
    try:
        if command == "key":
            mask, code = mask_of(args[0]), code_of(args[1])
        elif command in ("click", "scroll"):
            mask = mask_of(args[3])
        if mask or command == "key":
            keyboard = Keyboard(pointer.conn)
        if command == "key":
            keyboard.modifiers(mask)
            held_key = code
            keyboard.key(code, True)
            keyboard.key(code, False)
            held_key = None
        elif command == "move":
            pointer.motion(float(args[0]), float(args[1]))
        elif command == "click":
            button = BUTTONS[args[2]]
            pointer.motion(float(args[0]), float(args[1]))
            if mask:
                keyboard.modifiers(mask)
            held_button = button
            pointer.button(button, True)
            pointer.button(button, False)
            held_button = None
        elif command == "drag":
            x1, y1, x2, y2 = map(float, args)
            pointer.motion(x1, y1)
            held_button = BUTTONS["left"]
            pointer.button(held_button, True)
            steps = max(8, min(30, int(max(abs(x2 - x1), abs(y2 - y1)) / 10)))
            for i in range(1, steps + 1):
                time.sleep(0.016)
                pointer.motion(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
            pointer.button(held_button, False)
            held_button = None
        elif command == "scroll":
            pointer.motion(float(args[0]), float(args[1]))
            if mask:
                keyboard.modifiers(mask)
            pointer.scroll(AXIS_VERTICAL, int(args[2]))
        else:
            raise SystemExit(f"drive.py: unknown command {command!r}")
    finally:
        # Whatever failed, nothing stays held in the nested seat.
        try:
            if held_button is not None:
                pointer.button(held_button, False)
            if held_key is not None:
                keyboard.key(held_key, False)
            if keyboard is not None:
                if mask:
                    keyboard.modifiers(0)
                keyboard.close()
        finally:
            pointer.close()


if __name__ == "__main__":
    main(sys.argv[1:])
