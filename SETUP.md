# LaTeX rendering for CLI agents in a terminal

Claude Code and Codex write LaTeX; this stack turns it into real typeset images
inside a herdr pane, without giving up herdr's agent layer.

```
TFormula (PTY proxy: finds TeX, renders it via MathJax, emits a Kitty image)
  -> herdr pane      (Ghostty core decodes it, re-emits as a direct placement)
  -> herdr client
  -> outer terminal  (must actually speak the Kitty graphics protocol)
```

Every link has to hold. `files/verify.sh` checks all of them and names the one
that broke, so start there when something stops working — then look up the symptom
in [CAVEATS.md](CAVEATS.md), which lists every known failure mode with its cause,
its evidence, and what to do about it. Most of them fail *quietly*, so the symptom
rarely points at the cause on its own.

## Quick start on a fresh machine

```sh
git clone <this repo> && cd latex-terminal-setup
./install.sh          # steps 2-6 below, idempotent
./files/verify.sh     # from inside a herdr pane, run bare
```

`install.sh` deliberately leaves two things to you: the outer terminal (step 1 --
a human choice, and the one link that silently kills everything) and the Ghostty
palette (a preference). Re-running it is safe; it reports what is already in place
rather than appending again.

---

## 1. The outer terminal — the link that fails silently

The terminal that finally draws the pixels must implement the Kitty graphics
protocol. **Ghostty, kitty, and WezTerm qualify. Guake, gnome-terminal, xterm,
Windows Terminal, and PuTTY do not** — they discard the APC sequences without a
word.

Sitting at the machine, install Ghostty and use it. That is the most reliable
combination and needs no extra configuration beyond a palette you like.

### Connecting from Windows

Use **WezTerm's built-in SSH client**. Do not reach the box through
`wsl.exe` + `ssh`.

That route drags in **ConPTY**, which is not a pipe but a terminal emulator: it
parses the stream, keeps its own screen buffer, and re-serializes. Unknown APC
sequences are dropped, and DA/DSR queries are answered by ConPTY itself, so the
probe never reaches WezTerm. The tell is a Primary DA of
`ESC[?61;6;7;22;23;24;28;32;42c` with no reply to OSC 10/11; real WezTerm answers
`ESC[?65;4;6;18;22c`. Enabling `enable_kitty_graphics` changes nothing, because
the sequences never arrive.

WezTerm's own SSH client bypasses both WSL and ConPTY:

```lua
-- %USERPROFILE%\.wezterm.lua
config.ssh_domains = {
  {
    name = 'box',
    remote_address = '<host>:<port>',
    username = '<user>',
    -- Required unless wezterm-mux-server is installed on the remote: the
    -- default 'WezTerm' multiplexing tries to spawn it and fails.
    multiplexing = 'None',
    assume_shell = 'Posix',
  },
}
config.default_domain = 'box'

config.default_cursor_style = 'SteadyBlock'
config.cursor_blink_rate = 0
```

WezTerm's built-in SSH reads the **Windows-side** `~/.ssh/config` and keys, not
WSL's. A local shell is still available with `wezterm start --domain local`.

Caveat worth knowing: WezTerm's Kitty graphics support is partial — text drawn
over an image's cells punches holes in it (WezTerm issue #3817), so formulas can
look chewed in a TUI that redraws often. Ghostty does not have this problem.

## 2. herdr

```toml
# ~/.config/herdr/config.toml
[ui]
# Default "auto" only draws herdr's own cursor on Windows/WSL and uses the outer
# terminal's cursor elsewhere, so a pane app that asks for a blinking cursor via
# DECSCUSR (Claude Code does) blinks hard. "drawn" renders it as cell content.
host_cursor = "drawn"

[experimental]
# Without this herdr does not re-emit the pane's images to the client at all.
kitty_graphics = true
```

`herdr server reload-config` applies both live.

## 3. TFormula

```sh
npm install -g tformula
files/patch-tformula.sh
```

The patch makes formulas render in the terminal's **default foreground**. Without
it the image inherits the color of the source *cells*, so a syntax-highlighted
LaTeX block in an agent TUI paints the formula in the highlighter's color — dark
blue on a dark background, effectively invisible.

`npm update -g tformula` reverts it. The script is idempotent; re-run it after
every upgrade. It also clears the formula cache, otherwise renders keyed under
the old colors get reused.

## 4. Launchers

```sh
install -m755 files/hrmath files/hrclaude files/hrcodex ~/.local/bin/
install -m755 files/kittyprobe.py ~/.local/bin/   # optional, used by verify.sh
```

`hrmath` does two deliberate pieces of spoofing, both load-bearing:

- **`TERM_PROGRAM=ghostty`** — TFormula gates graphics on the terminal *name*
  (`/ghostty|kitty|wezterm/` against `"$TERM $TERM_PROGRAM"`). A herdr pane
  reports `TERM=xterm-256color`, but herdr's pane terminal *is* Ghostty's core
  and does answer the `a=q` query with OK, so the claim is accurate. TFormula
  still fails closed if that OK never arrives.

- **`exec -a "$kind"`** — herdr identifies a pane's agent from the foreground
  process's **`argv[0]`**, and it does not descend into TFormula's inner pty.
  Without the spoof the pane reads as `node .../tformula` and never appears in
  `herdr agent list`, which costs the sidebar entry, `hrname`, working/idle
  state, `herdr agent prompt/wait`, and notifications.

Also note `--min-readable-scale 0.3`: TFormula keeps a formula as raw TeX when it
would render below 0.4 of natural size. On a 4K screen a cell is ~18x38px and an
ordinary one-line formula lands at ~0.398, just under the default. Override per
run with `HRMATH_MIN_SCALE`.

`hrmath` finds TFormula by resolving the `tformula` shim on `PATH`, which is a
symlink straight to `dist/cli.js` — nothing machine-specific, and no `npm` call on
the hot path. It has to invoke `node` on that script rather than the shim, because
running the shim would leave `tformula` in `argv[0]` and break detection. If it
cannot resolve, it exits with a message instead of quietly running unwrapped.
Override with `TFORMULA_CLI` if your install is unusual.

## 5. Wrap the agents by default

Append `files/zshrc-snippet.zsh` to `~/.zshrc`. It replaces `claude` and `codex`
with functions that route through `hrmath`.

This is only safe *because* of the `argv[0]` spoof — otherwise wrapping by
default would silently cost the agent layer. Guards: only inside herdr, never
nested (`TFORMULA_ACTIVE`), only on a TTY, and never for the headless modes
(`claude -p`, `codex exec`), which must stay a clean pipe. Escape hatch:
`HRMATH_AGENTS=0`, or `command claude`.

TFormula is a PTY proxy, so an already-running agent cannot be wrapped
retroactively — relaunch it, resuming with `claude --resume <id>` or
`codex resume <id>` (herdr reports the ids as `agent_session.value`).

## 6. Tell the agents how to write math

Two formatting rules matter more than any setting, because **TFormula bounds the
image to the cell rectangle the source occupies**:

- **Display delimiters go on their own lines.** A one-line `$$...$$` is squeezed
  into a single row and comes out tiny; three lines give it three rows and about
  3x the size. Measured: 38px vs 114px for the same formula. Raising `--scale`
  does not help — the box is unchanged and only the fitted ratio drops
  (scale 1.0/1.5/2.0 all produced a 1836x38px image at fit 1.000/0.732/0.549).

- **At most one inline `$...$` per line**, and never mixed with CJK prose.
  TFormula merges several dollar-delimited spans on one line into a single
  formula and wraps the text between them in `\text{}`; MathJax has no CJK
  glyphs, so it renders broken.

Put these in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. Verified: both
agents complied on the first prompt after the rules were added.

## 7. Verify

```sh
files/verify.sh        # run it bare, inside a herdr pane -- not piped, not redirected
```

Redirecting stdout makes TFormula disable itself (it gates on `isTTY`), which
looks exactly like a broken terminal; the script refuses to run in that case.

Expected: **11 passed, 0 failed**, including `math=true`,
`delimiters on their own lines render taller (114px vs 38px)`, and
`argv[0]=claude is detected as a Claude agent`.

---

## When it breaks later

See [CAVEATS.md](CAVEATS.md). It is ordered by likelihood and each entry leads with
the symptom, because these failures are quiet: the setup keeps half-working and
nothing points at the cause.

The two you will actually meet: `npm update -g tformula` reverts the color patch
(formulas go blue), and a herdr change to how it identifies a pane's agent would
break detection (formulas render, pane vanishes from the sidebar).
