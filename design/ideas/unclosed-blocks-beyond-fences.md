# Unclosed blocks beyond fences

Found while checking test coverage (2026-11-11). Breaks the promise **"The same blocks as the
whole text"**, and **"Final means final"** with it. Some blocks besides fences can hold a blank line,
and kramdown only recognises them once their closing line arrives. Until then it reads paragraphs, so
`clean_cut?` agrees to a cut at the blank line inside, and the closing line can no longer undo it.
This is the trap the invariant **"No cut inside an unclosed fence"** guards against, but fences are
the only block tracked by hand.

## What breaks

Each fed one character at a time, against kramdown's parse of the whole text. Every case fails
even as a single delta, because the cut is taken while one `append` scans its lines:

| Reply (blank line inside) | Whole parse | Streamed |
|---|---|---|
| `$$` / `a = b` / *blank* / `c = d` / `$$` | one math block | two paragraphs, `$$` literal |
| `<!--` / *blank* / `hidden` / *blank* / `-->` | one HTML comment | three paragraphs, `hidden` shown |
| `{::comment}` … `{:/comment}` | one comment | three paragraphs, `hidden` shown |
| `{::nomarkdown}` … `{:/nomarkdown}` | raw `<b>x</b>` | three paragraphs |

The same blocks without a blank line inside stream fine, since there's no candidate cut. Some
blocks that hold blank lines already pass:

- `$$` inside a list item: the list stays open on its own.
- `<div>`, `<pre>` and `<script>`: kramdown's HTML parser closes an unclosed tag at the end of the
  text, so the parse disagrees and the cut is refused.

An HTML comment that hides text is the worst row: the text the reply meant to hide is shown, and
it's final.

`$$` display math is the row an LLM reply is most likely to hit, though a blank line inside display
math is unusual.

## Fix on the table

- **Generalise the hand-tracked fence into an open block with a closer.** `@fence` becomes "the
  closer awaited": the fence's `[char, length]`, `$$`, `-->`, or `{:/name}`. `scan` takes no cut
  while one is open, as it does for fences today. This doesn't go against
  `D_kramdown_judges_cuts`: a hand-written rule here only *refuses* a cut, never takes one. An
  opener matched too eagerly only holds the block open until `finish`; an opener missed is the bug.
  So the regexes may be loose on the open side and must be exact on the close side.
- Widen the invariant in `AGENTS.md` to "no cut inside an unclosed fence, math block, HTML comment
  or kramdown extension", and add each of them, with a blank line inside, to the property spec's
  reply.

## Open questions

- `Q_math_closer`: kramdown takes `$$` … `$$` as one regex across lines, so `$$ a = b $$` on one
  line opens and closes at once, and the closing `$$` may end a content line (`c = d $$`). Should the
  closer test be "the line contains `$$`" rather than "the line is `$$`"? Read
  `parser/kramdown/math.rb` before deciding; it's also the GFM parser's.
- `Q_comment_closer`: does kramdown end an HTML comment block at the first `-->` mid-line, and what
  becomes of text after it on that line? Same question for `{:/}`, the short extension closer, and
  for the self-closing `{::comment /}`, which opens nothing.
- `Q_other_html`: `<div>`, `<pre>` and `<script>` pass because kramdown closes an unclosed tag at
  the end of the text. Is that true of every block-level tag, or does some tag (`<textarea>`?) read
  as a paragraph until it closes? Probe kramdown's `HTML_CONTENT_MODEL` list rather than guessing.
