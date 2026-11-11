# Decisions

Why this project is the way it is and not otherwise — FAQ-shaped: each entry is a question and
its current answer. Rewrite the answer when it changes; delete the entry when nobody asks any
more. An entry is earned by what it would cost to reverse — half the code base — or by research
the next person would otherwise redo (cited as its `R_`). Not an entry: windows → panels
"because that's the trend", this red over that red, `get_foo` over `is_foo?`, the testing library,
the CI host, a version bump — a comment at the site of the choice, or nothing; nothing about
`design/` itself. Cite by slug, `D_<slug>`, never by position; `grep '^## D_' design/decisions.md`
is the index. The first entry is the ruler: every later one trims to its length — which is how
long this file gets, so keep it short. When you have written an entry, re-read it against the one
above, open the doc comments it touches and cut what they already say, then cut the fat.

---

## D_block_events — Why block events rather than inline events, StAX-style, or slices of source?

A listener gets each finished top-level block once, as a kramdown root, and the open tail,
provisional, after every delta. Why not inline events (`start_strong`, `text`, `end_strong`), as
an XML stream parser emits them: XML is unambiguous from left to right, and Markdown is not.
`**bol` is bold or two asterisks depending on a closer that may never come, a closing fence turns
earlier lines into code, and a wider row re-pads a table, so inline events would need
retractions that every listener has to undo. A block is settled once the next one has begun. Why
not slices of source, the committed and the open text: each app would parse them again, and
re-render all its committed text to keep a loose list whole, which is the work this gem exists to
share. Why kramdown trees rather than our own: the apps already convert kramdown, and a block
wrapped in its own root goes into any converter unchanged.

## D_kramdown_judges_cuts — Why let kramdown judge each cut rather than hand-written Markdown rules?

A cut is taken only where kramdown parses the open text before it and the next line alone into
the same blocks as both together. Why not rules, such as "commit at every blank line outside a
fence": a loose list, an indented continuation, a fence inside a list item and a definition all
span blank lines, and each rule only approximates kramdown, which isn't CommonMark either.
Committing early is the one mistake a final block can't take back; kramdown's agreement makes the
cut as right as the parse of the whole text, for two small extra parses per candidate. Blocks that
only their closer ends — fences, `$$`, HTML comments, `{::comment}` and kin — are tracked by hand:
inside an unclosed one, kramdown sees paragraphs, and would agree to a cut that the closer then
undoes. A hand rule there only refuses cuts, and kramdown still judges whether a line opens such a
block: one held open by mistake hides the fence inside it.

## D_references_stay_literal — Why does a reference a block away from its definition stay literal rather than resolve?

kramdown resolves `[text][1]` and `[^a]` against definitions anywhere in the text, but each side
of a cut is parsed alone. Its agreement keeps a definition with the block right next to it; one a
block or more away, before or after, leaves the reference literal and the definition rendering as
nothing. Why not resolve it: a definition yet to come can't be known, so being right means taking
final blocks back, a reset that resends the whole reply. Why not carry committed definitions into
later parses (kramdown's `link_defs:`): it mends only the backward half, footnotes have no such
option, and the end-of-reply render fixes both anyway. Why not hold the cut while kramdown warns
of a missing definition: bare `[brackets]` in prose warn alike, and such a reply never streams.
An LLM reply ends whole, so the app renders it once more with `parse`, which resolves them all.
