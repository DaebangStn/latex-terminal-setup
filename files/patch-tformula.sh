#!/bin/sh
# Make TFormula render formulas in the terminal's default foreground.
#
# Without this the image inherits the color of the source *cells*, so a
# syntax-highlighted LaTeX block in an agent TUI paints the formula in the
# highlighter's color -- dark blue on a dark background, unreadable.
#
# Re-run after every `npm update -g tformula`: this edits the installed dist/.
set -eu

CLI_DIR=$(dirname "$(node -e 'console.log(require.resolve("tformula/dist/screen.js"))' 2>/dev/null)" || true)
if [ -z "${CLI_DIR:-}" ] || [ ! -f "$CLI_DIR/screen.js" ]; then
  # require.resolve fails for a global install; fall back to npm's root.
  CLI_DIR="$(npm root -g)/tformula/dist"
fi
TARGET="$CLI_DIR/screen.js"
[ -f "$TARGET" ] || { echo "screen.js not found at $TARGET" >&2; exit 1; }

if grep -q 'foreground: this.#capabilities.foreground' "$TARGET"; then
  echo "already patched: $TARGET"
  exit 0
fi

cp "$TARGET" "$TARGET.bak"
TARGET="$TARGET" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["TARGET"])
s = p.read_text()
anchor = """                    renderColors = {
                        foreground: currentPresentation.foreground,
                        background: currentPresentation.background
                    };
                }
"""
if s.count(anchor) != 1:
    raise SystemExit("anchor not found exactly once (%d) -- tformula changed, patch by hand" % s.count(anchor))
patch = """                // Render formulas in the terminal's default foreground instead of the
                // source cells' color. Normalized before the fingerprint so the cache
                // key matches what is drawn. LOCAL PATCH; reverts on npm update.
                renderColors = { ...renderColors, foreground: this.#capabilities.foreground };
"""
p.write_text(s.replace(anchor, anchor + patch))
print("patched", p)
PY
node --check "$CLI_DIR/screen.js"
tformula cache clear >/dev/null 2>&1 || true
echo "done -- cache cleared so old colored renders are not reused"
