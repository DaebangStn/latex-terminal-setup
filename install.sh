#!/bin/bash
# Install the LaTeX-in-terminal stack on a fresh machine. Idempotent: re-running
# reports what is already in place instead of duplicating it.
#
# Not automated on purpose:
#   - the outer terminal (SETUP.md step 1) -- a human choice, and the one link
#     that silently kills everything if it cannot speak Kitty graphics
#   - verification (SETUP.md step 7) -- run files/verify.sh from a herdr pane
set -uo pipefail
cd "$(dirname "$0")"

changed=0
add()  { printf '  +  %s\n' "$1"; changed=$((changed+1)); }
keep() { printf '  =  %s\n' "$1"; }
warn() { printf '  !  %s\n' "$1"; }

need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  warn "$1 not found -- $2"
  return 1
}

echo "== prerequisites =="
need node "install Node (nvm is fine); TFormula is an npm package" || exit 1
need npm  "comes with Node" || exit 1
need herdr "install herdr first: https://herdr.dev" || exit 1
need python3 "used by the herdr integration hooks and by verify.sh" || true

echo "== TFormula =="
if command -v tformula >/dev/null 2>&1; then
  keep "tformula already installed ($(tformula --version 2>/dev/null | head -1))"
else
  npm install -g tformula >/dev/null && add "tformula installed" \
    || { warn "npm install -g tformula failed"; exit 1; }
fi
./files/patch-tformula.sh | sed 's/^/  /'

echo "== launchers =="
mkdir -p "$HOME/.local/bin"
for f in hrmath hrclaude hrcodex kittyprobe.py; do
  if [ -f "$HOME/.local/bin/$f" ] && cmp -s "files/$f" "$HOME/.local/bin/$f"; then
    keep "~/.local/bin/$f"
  else
    install -m755 "files/$f" "$HOME/.local/bin/$f" && add "~/.local/bin/$f"
  fi
done
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) warn "~/.local/bin is not on PATH -- add it to ~/.zshrc" ;;
esac

# hrmath resolves TFormula from the `tformula` PATH shim (a symlink to
# dist/cli.js), so there is nothing machine-specific to rewrite. Just confirm it
# resolves -- if it cannot, hrmath refuses to run rather than silently dropping
# the argv[0] spoof that herdr's agent detection depends on.
if shim=$(command -v tformula 2>/dev/null) && [ -f "$(readlink -f "$shim")" ]; then
  keep "hrmath will resolve TFormula via $shim"
else
  warn "tformula not resolvable on PATH -- hrmath will refuse to start"
fi

echo "== herdr config =="
hcfg="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"
mkdir -p "$(dirname "$hcfg")"; touch "$hcfg"
if grep -qE '^\s*kitty_graphics\s*=\s*true' "$hcfg"; then
  keep "experimental.kitty_graphics = true"
else
  warn "adding [experimental]/[ui] blocks -- review $hcfg afterwards"
  cat files/herdr-config-snippet.toml >> "$hcfg"
  add "herdr config appended"
fi
grep -qE '^\s*host_cursor\s*=\s*"drawn"' "$hcfg" \
  && keep 'ui.host_cursor = "drawn"' \
  || warn 'ui.host_cursor is not "drawn" -- the cursor will blink; see the snippet'
herdr server reload-config >/dev/null 2>&1 \
  && keep "herdr config reloaded" \
  || warn "could not reload herdr config (no server running?) -- it applies on next start"

echo "== shell wrappers =="
zrc="$HOME/.zshrc"; touch "$zrc"
if grep -q '_hrmath_should_wrap' "$zrc"; then
  keep "~/.zshrc already wraps claude/codex"
else
  printf '\n' >> "$zrc"; cat files/zshrc-snippet.zsh >> "$zrc"
  add "~/.zshrc wrappers appended (open a new shell to pick them up)"
fi

echo "== agent instructions =="
append_section() {  # $1 target file, $2 snippet
  mkdir -p "$(dirname "$1")"; touch "$1"
  if grep -q '^## Math in terminal output' "$1"; then
    keep "$1 already has the math section"
  else
    printf '\n' >> "$1"; cat "$2" >> "$1"
    add "$1 math section appended"
  fi
}
append_section "$HOME/.claude/CLAUDE.md" files/claude-md-snippet.md
append_section "$HOME/.codex/AGENTS.md" files/agents-md-snippet.md

echo "== ghostty (only if you run Ghostty on this machine) =="
gcfg="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
if command -v ghostty >/dev/null 2>&1; then
  if [ -f "$gcfg" ] && grep -q '^theme' "$gcfg"; then
    keep "ghostty config already sets a theme"
  else
    warn "not touching $gcfg -- palette is a preference"
    warn "see files/ghostty-config-snippet for what this box uses"
  fi
else
  keep "ghostty not installed here (fine if you connect from elsewhere)"
fi

printf '\n%d change(s) applied.\n' "$changed"
cat <<'EOF'

Next, by hand:
  1. Make sure the terminal that draws the pixels speaks Kitty graphics
     (Ghostty / kitty / WezTerm). From Windows use WezTerm's built-in SSH --
     never wsl.exe + ssh, which routes through ConPTY and eats the images.
     SETUP.md step 1 has the .wezterm.lua.
  2. From inside a herdr pane, run it bare (not piped, not redirected):
       ./files/verify.sh
     Expect: 11 passed, 0 failed.
EOF
