## Math in terminal output

- These sessions run under TFormula (launched via `hrmath`/`hrcodex`, or the
  auto-wrapping `codex` function in `~/.zshrc`), which renders
  LaTeX as images in the terminal. So write real LaTeX, not Unicode
  approximations. Check `TFORMULA_ACTIVE=1` if you need to know whether the
  current session has it; when it is unset, fall back to plain Unicode.

- **Keep the formula body on a single line.** Never leave `=` or `-` alone on a
  line inside a display block: your own Markdown renderer reads it as a setext
  heading underline, turns the lines above it into a heading, and *deletes* the
  `=` line before TFormula ever sees the text. TFormula then faithfully renders
  the mutilated LaTeX. Use `\\` if you need a line break inside the formula.

  ```
  $$
  P(\mathrm{overflow}\mid\mathrm{NaN}) = \frac{17}{17} = 1
  $$
  ```

- **Put the display delimiters on their own lines**, as above. TFormula bounds the
  rendered image to the cell rectangle the source occupies, so a one-line
  `$$...$$` is squeezed into a single row and comes out tiny; three lines give it
  three rows and roughly 3x the size. Raising `--scale` does not help — it only
  lowers the fitted ratio inside the same box.

- **At most one inline `$...$` per line**, and do not mix inline math with Korean
  prose on the same line. TFormula merges several dollar-delimited spans on one
  line into a single formula and wraps the text between them in `\text{}`;
  MathJax has no Korean glyphs, so that renders broken. Split the formulas onto
  separate display blocks instead.

- Long derivations still belong in display blocks, one equation per block, rather
  than a code fence — a fenced block is syntax-highlighted, and TFormula colors
  the image from the source cells.
