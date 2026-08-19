## Math in terminal output

- These sessions run under TFormula (via `hrmath`/`hrcodex`, or the auto-wrapping
  `codex` function in `~/.zshrc`), which renders LaTeX as images in the terminal.
  Write real LaTeX, not Unicode approximations. `TFORMULA_ACTIVE=1` tells you the
  current session has it; when unset, fall back to plain Unicode.

- **Put display delimiters on their own lines.** TFormula bounds the image to the
  cell rectangle the source occupies, so a one-line `$$...$$` is squeezed into a
  single row and comes out tiny. Three lines give three rows and roughly 3x the
  size. Raising `--scale` does not help — it only lowers the fitted ratio inside
  the same box.

  ```
  $$
  E = mc^2
  $$
  ```

- **At most one inline `$...$` per line**, and do not mix inline math with Korean
  prose on the same line. TFormula merges several dollar-delimited spans on one
  line into one formula and wraps the text between them in `\text{}`; MathJax has
  no Korean glyphs, so it renders broken. Use separate display blocks instead.

- Keep derivations in display blocks, one equation per block, rather than a code
  fence — a fence is syntax-highlighted and TFormula colors the image from the
  source cells.
