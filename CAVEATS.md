# Caveats

Everything here is known, measured, and deliberately left in place. Nothing is a
mystery to be rediscovered — the point of this file is that when one of these
surfaces, you recognize it in one line instead of spending an afternoon on it.

They are ordered by how likely you are to hit them.

The dangerous property they share is that **most of them fail quietly**: the
setup keeps half-working, so the symptom does not point at the cause. That is why
each entry below leads with the symptom.

---

## 1. A formula renders with pieces missing → Markdown ate the `=` line

**Cause.** Not TFormula. An agent renders its own Markdown *before* the text
reaches the terminal, and Markdown has a setext heading rule: a line containing
only `=` turns the paragraph above it into a level-1 heading and is consumed. So a
display block written like this

```
$$
P(\mathrm{overflow}\mid\mathrm{NaN})
=
\frac{17}{17}
=
1
$$
```

reaches the screen as a heading with the `=` lines *deleted*. TFormula then
faithfully renders the mutilated LaTeX. Recorded in `tformula history` as:

```
P(\mathrm{overflow}\mid\mathrm{NaN})\n\n\frac{17}{17}\n\n1
```

The tell is in the cells: the affected lines carry `ESC[1m ESC[4m` (bold +
underline, i.e. heading styling) and a `# ` prefix, and the `=` lines are blank.
`-` has the same problem — it is the level-2 setext underline.

**Why it does not reproduce in a bare shell.** `cat`ing the same block through
`hrmath` renders it perfectly, because there is no Markdown renderer in the path.
Multi-line bodies, nested-looking sub-formulas, and slow streaming were all tested
this way and all came back intact. The corruption needs an agent's Markdown stage.

**Fix.** A source-formatting rule, so it lives in the agents' instruction files:
keep the formula body on a single line and use `\\` for breaks inside the
formula. See `files/claude-md-snippet.md`.

## 2. Formulas turn blue again → the tformula patch was reverted

**Cause.** The formula image inherits the color of the source *cells*. A
syntax-highlighted LaTeX block in an agent TUI therefore paints the formula in the
highlighter's color — dark blue on a dark background, effectively invisible.
`files/patch-tformula.sh` normalizes it to the terminal's default foreground by
editing the installed `dist/screen.js`:

```js
renderColors = { ...renderColors, foreground: this.#capabilities.foreground };
```

tformula is a third-party npm package with no local source checkout, so
`npm update -g tformula` silently undoes this.

**Fix.** Re-run `files/patch-tformula.sh`. It is idempotent and clears the formula
cache (without that, renders keyed under the old colors get reused).

**What an upstream fix would look like.** Render proxy-path formulas in the
terminal default foreground, or expose an option. The reader path
(`reader.js:509`) already does the right thing; only the proxy path
(`screen.js:2067`) takes the source color.

## 3. Formulas render but the pane is missing from the sidebar → argv[0] detection changed

**Cause.** herdr identifies a pane's agent from the foreground process's
**`argv[0]`**, not `comm` — measured: `exec -a claude sleep 300` is detected as
Claude. It enumerates only the pane's foreground process group and does not
descend into TFormula's inner pty. `hrmath` depends on that:

```sh
exec -a "$kind" node "$TFORMULA_CLI" --min-readable-scale "$MIN_SCALE" "$kind" "$@"
```

Without the spoof the pane reads as `node .../tformula` and never appears in
`herdr agent list`, which costs the sidebar entry, `hrname`, working/idle state,
`herdr agent prompt/wait`, and notifications.

**This is observed behavior, not a documented herdr contract.** If herdr starts
matching `comm` or the executable path, it breaks.

**Fix.** Drop `exec -a` from `hrmath` — and accept that detection under a PTY
proxy is then unrecoverable, because both alternatives were measured and neither
works:

- Manifest `aliases` are *kind* aliases used for manifest lookup, not process
  names, and the kind list is compiled into the binary. Local overrides do load
  from `~/.config/herdr/agent-detection/<id>.toml`, but they freeze remote rule
  updates for that agent and cannot help here.
- `herdr pane report-agent` registers a pane well enough for `agent list`, the
  sidebar, `rename`, `get`/`wait`/`focus` — but `agent prompt` and `send-keys`
  re-verify the foreground process and fail with `agent_not_ready`. Driving the
  lifecycle from agent hooks cannot restore the input path.

Filing a herdr feature request is not currently possible: it has no public issue
tracker.

## 4. Formulas stop rendering entirely from Windows → ConPTY is back in the path

**Cause.** `wezterm → wsl.exe → ssh` routes through **ConPTY**, which is not a
pipe but a terminal emulator: it parses the stream, keeps its own screen buffer,
and re-serializes. Unknown APC sequences are dropped and DA/DSR queries are
answered by ConPTY itself, so the capability probe never reaches WezTerm.
`enable_kitty_graphics` changes nothing, because the sequences never arrive.

**How to recognize it in one command.** `files/kittyprobe.py` prints the raw
replies:

| | Primary DA | OSC 10/11 | kitty `a=q` |
|---|---|---|---|
| through ConPTY | `ESC[?61;6;7;22;23;24;28;32;42c` | no reply | no reply |
| real WezTerm | `ESC[?65;4;6;18;22c` | answers | `OK` |

**Fix.** Use WezTerm's built-in SSH client (SETUP.md step 1), which bypasses both
WSL and ConPTY.

## 5. Formulas stay as raw TeX → fitted scale below the floor

**Cause.** TFormula keeps a formula as raw TeX when it would render below
`--min-readable-scale` (default 0.4) of natural size. On a 4K screen a cell is
~18x38px and an ordinary one-line formula lands at ~0.398 — just under. The log
line is explicit:

```
[tformula] kept raw TeX at normal:0:0: fitted scale 0.398 is below 0.400
```

**Fix.** `hrmath` already defaults it to 0.3. Override per run with
`HRMATH_MIN_SCALE`.

## 6. Display formulas look too small → the image is bounded by the source's cell rectangle

**Cause.** TFormula bounds the rendered image to the cell rectangle the source
text occupies, so a one-line `$$...$$` gets a single row of height and the glyphs
end up smaller than the terminal's own text. Measured (cell 18x38px):

| source | rendered |
|---|---|
| `$$E = mc^2$$` on one line | `1836x38px` (1 row) |
| `$$` / `E = mc^2` / `$$` on three lines | `1836x114px` (3 rows) |

`--scale` cannot fix it — the box is unchanged and only the fitted ratio drops.
It is also capped at 2:

```
scale 1.0 -> 1836x38px, fit 1.000
scale 1.5 -> 1836x38px, fit 0.732
scale 2.0 -> 1836x38px, fit 0.549
```

**Fix.** A source-formatting rule, which is why it lives in the agents'
instruction files: display delimiters go on their own lines. See
`files/claude-md-snippet.md`.

**What an upstream fix would look like.** Let a display formula claim more rows
than its source occupies, or expose a minimum row count.

## 7. An inline formula "does not render" → several `$...$` on one line got merged

**Cause.** TFormula joins several dollar-delimited spans on a single line into one
formula and wraps the text between them in `\text{}`. MathJax has no CJK glyphs,
so the result renders broken. Observed — this source line:

```
인라인 테스트: $E = mc^2$, 그리고 ( \gamma = 1/\sqrt{1 - v^2/c^2} ).
```

was recorded in `tformula history` as a *single* inline formula:

```
E = mc^2\text{, 그리고 }\gamma = 1/\sqrt{1 - v^2/c^2}
```

So there is no standalone `E = mc^2` image, and the merged blob has unrenderable
glyphs in the middle. Relevant code: `dollarDelimiterPositions()`
(`detect.js:550`) and `dollarDelimitedSegments()` (`detect.js:564`).

**Fix.** At most one inline `$...$` per line, and never mixed with CJK prose — put
formulas in separate display blocks. Encoded in the agents' instruction files.

## 8. Stray little images around a formula → wrapped source in a narrow pane

**Cause.** When a display formula's raw source wraps across several terminal lines
in a narrow pane, TFormula also infers fragments of the wrapped text as separate
inline formulas and renders them. Observed right after a correctly formatted
three-line `$$` block in a half-width pane:

```
display=False | \mathbf{r},t
display=False | \mathbf{r},t\text{ =}
display=False | ↓
```

Harmless — the display formula itself is fine — but the strays are visible.
Probably the same root cause as caveat 7.

**Fix.** Wider panes for math-heavy output, or shorter formulas.

## 9. Formulas look chewed or partially erased in WezTerm

**Cause.** WezTerm implements the Kitty graphics protocol only partially: it maps
an image to cells at placement time, so text later drawn over those cells punches
through it. An agent TUI redraws constantly, so formulas get eaten. kitty and
Ghostty do not behave this way. Upstream:
[wezterm#3817](https://github.com/wezterm/wezterm/issues/3817).

**Fix.** None on our side. This is why local Ghostty is the recommended setup and
WezTerm is only the remote route.

## 10. `verify.sh` reports `math=false` on a working setup → stdout was redirected

**Cause.** TFormula gates on `isTTY` and needs the terminal to answer the
cell-size query, so `./verify.sh > log` or piping it makes every render check fail
in a way that looks exactly like a broken terminal. `verify.sh` refuses to run in
that case, but it is worth knowing why.

**Fix.** Run it bare, from a herdr pane.

## 11. One pane's background is oddly tinted — root cause unidentified

**Cause.** An app inside that pane set a default background via OSC 11 and never
reset it. herdr tracks that per pane and carries it to the client
(`has_transient_default_color_override`, `parse_default_color_events`,
`write_host_default_color`), which is why it is invisible to
`herdr pane read --format ansi` — that shows only cell SGR — and why it is
unrelated to agent state. Verified both directions in a scratch pane:

```
printf '\033]11;#3a3a2a\033\\'  -> pane answers  ]11;rgb:3a3a/3a3a/2a2a\
printf '\033]111\033\\'         -> no reply, back to baseline
```

**Still unknown:** which app set it. Not every codex pane was tinted, so it was
most likely a leftover from something that set the background and exited without
resetting, rather than codex itself. It has not recurred since being cleared.

**Fix.** Reset it with `printf '\033]111\033\\'`. If an agent is running in that
pane, write to the pty **slave** instead — that appears as app output and never
reaches the agent's stdin:

```sh
herdr pane process-info --pane <pane_id>   # -> foreground pid
ls -l /proc/<pid>/fd/0                     # -> /dev/pts/N
printf '\033]111\033\\' > /dev/pts/N
```

No config key disables the behavior; `[theme.custom]` only affects herdr's own UI
colors.

---

## Scope limits, not bugs

- **`install.sh` assumes zsh.** It appends the wrapper functions to `~/.zshrc`.
  Bash and fish users need to port `files/zshrc-snippet.zsh` by hand.
- **The outer terminal is never configured automatically.** It is a human choice
  and the one link that silently kills everything, so `install.sh` only tells you
  what is required.
- **The Ghostty palette is not applied automatically** either; it is a preference.
  `files/ghostty-config-snippet` records what this setup uses.
- **herdr's `kitty_graphics` is flagged experimental** by herdr itself. A herdr
  update could change its behavior.
