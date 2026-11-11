# References resolve across cuts

Found while weighing pikuri-web's move onto this gem (2026-11-11). Breaks the promise **"The same
blocks as the whole text"**: kramdown resolves link definitions and footnotes against the *whole*
document, and a cut parses each side alone. A block committed before its definition arrives is
final and wrong.

## What breaks

Each fed one character at a time, against `Kramdown::Document.new(md, input: 'GFM').to_html`:

| Reply | Whole parse | Streamed |
|---|---|---|
| `See [the docs][1].` … `[1]: https://example.com` at the end | a link | literal `See [the docs][1].` |
| `Claim one.[^a]` … `[^a]: Source A.` at the end | numbered ref + footnotes list | literal `[^a]`; the definitions vanish |
| `[1]: url`, `See [a][1].`, `More.`, `Again [b][1].` | two links | first a link, `Again [b][1].` literal |
| `[^a]: A.`, `Claim[^a].`, `More.`, `Again[^a].` | one footnotes list, refs `fnref:a`, `fnref:a:1` | resolves, but each block converts with its own footnotes `<div>`: two lists, duplicate `id="fn:a"` / `id="fnref:a"` |

The definition-*first* case is half right by kramdown's own agreement: `clean_cut?` refuses the cut
between `[1]: url` and the paragraph using it (the line alone parses differently), so they commit
together. But once committed, the definition is gone from every later parse of the open tail, so
the *next* use of `[1]` is literal (row 3).

Why the property spec stayed green: its `reply` has no reference link and no footnote, so the
convention "a new construct joins the reply" never fired for them. Both belong in it, definition
last *and* definition first with a reuse after a cut.

Reference-style citations and footnotes are how a model cites web-search results, so this is not
an edge case for an LLM reply.

## Related, but the converter's: heading ids

Two `## Summary` headings: the whole parse gives `id="summary"` and `id="summary-1"`; per-block
conversion gives `id="summary"` twice, because the dedup lives in the converter instance. Not a
parse difference (the trees match), so not this gem's bug, but every consumer walks into it. At
least the README should say: one converter for the whole reply, or `auto_ids: false`. Footnote
numbering (row 4) is the same shape of problem on the converter side.

## Fixes on the table

- **A: verify at `finish`.** Parse the whole source once; if its shape differs from the committed
  blocks, `on_reset` and resend every block. One extra parse per reply, reuses the existing reset
  path. Final output becomes correct; mid-stream the committed blocks were still wrong, and "final
  means final" now has a second, quieter reason to reset.
- **B: carry definitions forward.** kramdown takes a `link_defs:` option (`update_link_definitions`
  in `parser/kramdown.rb`); feed every definition seen in committed text into each later parse.
  Fixes row 3 at the root, keeps blocks final. Does nothing for definition-last (rows 1, 2), and
  footnote definitions have no such option.
- **C: hold the cut while a reference is unresolved.** kramdown already reports it in
  `Document#warnings` ("No link definition for link ID '1' found", "Footnote definition for 'a'
  not found"). Refuse a cut whose head parse warns so. Correct by construction and keeps "final
  means final", but bare `[brackets]` in prose warn the same way, so such a reply stays open until
  `finish`, which means it streams like the whole-text re-render this gem exists to avoid.
- Likely answer: **B + A**. B keeps the common case final and correct; A is the backstop for
  definition-last, where no streaming parser can be right without retracting.

## Open questions

- `Q_reset_granularity`: A's `on_reset` resends *every* block. Could it resend only from the first
  differing block on, or does that need a new listener call (`on_reset(from:)`)? pikuri-web would
  want the smaller one: a reset re-sends the whole message over SSE.
- `Q_footnote_list`: who owns the footnotes `<div>`? Per-block conversion emits one per block that
  carries a footnote. The gem could hand footnote definitions to the listener separately (an
  `on_footnotes` call, or on the last block's root), or declare it the converter's problem.
- `Q_link_defs_source`: B needs the definitions out of a parse. kramdown's parser keeps
  `@link_defs` private and the root does not carry them; a parser subclass, or a regex over the
  committed text (`^ {0,3}\[[^\]]+\]:`)? The regex must agree with kramdown or B reintroduces the
  hand-written-rules problem `D_kramdown_judges_cuts` exists to avoid.
- `Q_promise_wording`: if only A ships, "The same blocks as the whole text" holds only after
  `finish`. Reword the promise, or is that a sign A alone is not enough?
