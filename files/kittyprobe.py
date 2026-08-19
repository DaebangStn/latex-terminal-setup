#!/usr/bin/env python3
"""Ask the OUTER terminal whether it speaks the Kitty graphics protocol.

Run this in a plain SSH shell (NOT inside herdr) so the replies come from the
real terminal. TFormula gives up silently when the OK never arrives, so this
prints the raw bytes instead of a verdict you have to trust.
"""
import os, sys, tty, termios, select

# Exactly what TFormula asks (probe.js:15,291): cell size, fg/bg, then the
# graphics capability query. Image id 2e9 is TFormula's KITTY_QUERY_IMAGE_ID.
PROBES = [
    ("cell size + fg/bg", "\x1b[16t\x1b[14t\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b[c"),
    ("kitty a=q, i=2000000000 (TFormula's id)",
     "\x1b[c\x1b_Gi=2000000000,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\"),
    ("kitty a=q, i=31 (small id)",
     "\x1b[c\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\"),
]

def ask(payload, wait=1.5):
    fd = os.open("/dev/tty", os.O_RDWR)
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        os.write(fd, payload.encode())
        buf = b""
        while select.select([fd], [], [], wait)[0]:
            chunk = os.read(fd, 4096)
            if not chunk:
                break
            buf += chunk
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        os.close(fd)
    return buf

results = [(label, ask(payload)) for label, payload in PROBES]
print("TERM=%s  TERM_PROGRAM=%s" % (os.environ.get("TERM"), os.environ.get("TERM_PROGRAM")))
for label, raw in results:
    print("\n%s\n  raw: %r" % (label, raw))
    if b"OK" in raw:
        print("  --> kitty graphics SUPPORTED")
    elif b"_G" in raw:
        print("  --> replied to _G but not OK (see raw)")
    else:
        print("  --> no _G reply")
