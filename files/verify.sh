#!/bin/bash
# Verify the LaTeX-in-terminal chain. Run this INSIDE a herdr pane, from a TTY.
#   ./verify.sh
# Every check prints PASS or FAIL with the evidence it used, so a failure tells
# you which link broke rather than just "not working".
set -uo pipefail
pass=0; fail=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
note() { printf '        %s\n' "$1"; }

echo "== 0. environment =="
[ "${HERDR_ENV:-}" = 1 ] && ok "inside a herdr pane ($HERDR_PANE_ID)" \
                         || no "not inside herdr -- run this in a herdr pane"
if [ -t 0 ] && [ -t 1 ]; then
  ok "stdin/stdout are a TTY"
else
  no "stdout is redirected -- run this bare, not piped or '> file'"
  note "tformula gates on isTTY, so every render check below would fail spuriously"
  exit 1
fi
command -v hrmath >/dev/null && ok "hrmath on PATH" || no "hrmath missing"
command -v tformula >/dev/null && ok "tformula on PATH" || no "tformula missing (npm i -g tformula)"

echo "== 1. herdr config =="
cfg=${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml
grep -qE '^\s*kitty_graphics\s*=\s*true' "$cfg" 2>/dev/null \
  && ok "experimental.kitty_graphics = true" \
  || no "kitty_graphics not enabled in $cfg -- herdr will not re-emit images"
grep -qE '^\s*host_cursor\s*=\s*"drawn"' "$cfg" 2>/dev/null \
  && ok 'ui.host_cursor = "drawn" (no cursor blink)' \
  || note 'ui.host_cursor is not "drawn" -- cosmetic only; the cursor may blink'

echo "== 2. tformula color patch =="
screen=$(npm root -g 2>/dev/null)/tformula/dist/screen.js
if grep -q 'foreground: this.#capabilities.foreground' "$screen" 2>/dev/null; then
  ok "color patch applied ($screen)"
else
  no "color patch missing -- run patch-tformula.sh, else formulas take the highlighter's color"
fi

echo "== 3. outer terminal speaks Kitty graphics =="
probe=$(dirname "$0")/kittyprobe.py
if python3 "$probe" 2>/dev/null | grep -q 'kitty graphics SUPPORTED'; then
  ok "terminal answered the a=q query with OK"
else
  no "no _G reply -- the outer terminal (or something in between) eats APC sequences"
  note "on Windows this is almost always ConPTY: use WezTerm's built-in SSH,"
  note "never 'wsl.exe + ssh'. See SETUP.md step 1."
fi

echo "== 4. tformula renders, and a 3-line block gets 3 rows =="
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '$$\nE = mc^2\n$$\n' > "$tmp/block.tex"
printf '$$E = mc^2$$\n'     > "$tmp/oneline.tex"
# stdout must stay on the TTY: tformula disables itself when it is redirected,
# and it needs the terminal to answer the cell-size query. The formulas below are
# therefore drawn on screen -- that is also the visual half of this check.
hrmath --debug sh -c "cat $tmp/block.tex; sleep 4" 2>"$tmp/block.err"
hrmath --debug sh -c "cat $tmp/oneline.tex; sleep 4" 2>"$tmp/one.err"
grep -q 'math=true' "$tmp/block.err" && ok "math=true (graphics gate passed)" \
  || { no "math=false -- tformula disabled itself"; note "$(head -1 "$tmp/block.err")"; }
bh=$(sed -n 's/.*rendered .*px, .*/&/p' "$tmp/block.err" | sed -n 's/.*(\([0-9]*\)x\([0-9]*\)px.*/\2/p' | head -1)
oh=$(sed -n 's/.*rendered .*px, .*/&/p' "$tmp/one.err"   | sed -n 's/.*(\([0-9]*\)x\([0-9]*\)px.*/\2/p' | head -1)
if [ -n "${bh:-}" ] && [ -n "${oh:-}" ] && [ "$bh" -gt "$oh" ]; then
  ok "delimiters on their own lines render taller (${bh}px vs ${oh}px)"
else
  no "could not confirm the multi-row box (block=${bh:-none} oneline=${oh:-none})"
  note "if both are 'none', nothing rendered -- check step 3"
fi

echo "== 5. herdr still detects an agent whose argv[0] is spoofed =="
# The mechanism hrmath relies on. Costs nothing -- no agent is started, just a
# `sleep` renamed to `claude`. It has to be the *sole* foreground process of a
# pane, so use a scratch pane rather than backgrounding it here.
if [ "${HERDR_ENV:-}" = 1 ] && command -v herdr >/dev/null; then
  sp=$(herdr pane split --current --direction down --no-focus 2>/dev/null \
       | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])' 2>/dev/null)
  if [ -n "${sp:-}" ]; then
    sleep 2
    herdr pane run "$sp" 'exec -a claude sleep 12' >/dev/null 2>&1
    sleep 5
    if herdr agent get "$sp" 2>/dev/null | grep -q '"agent":"claude"'; then
      ok "argv[0]=claude is detected as a Claude agent"
    else
      no "argv[0] spoofing no longer fools detection -- drop 'exec -a' from hrmath"
      note "symptom in daily use: formulas render but the pane is missing from the sidebar"
    fi
    herdr pane close "$sp" >/dev/null 2>&1
  else
    note "skipped: could not create a scratch pane"
  fi
else
  note "skipped (needs a herdr pane)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
