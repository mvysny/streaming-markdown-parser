# streaming-markdown-parser — AGENTS.md

## What this is

Parses Markdown as it streams in, an LLM's reply delta by delta, into top-level kramdown blocks.
Each finished block reaches your listener once and never changes; the unfinished tail comes
again, provisional, on every delta. It draws nothing: the terminal, the web page or the window
keeps its own kramdown converter.

## Promises

- **Final means final.** A block handed to `on_block` never changes; when in doubt, a block stays open.
- **The same blocks as the whole text.** However a reply is cut into deltas, its finished blocks are kramdown's parse of all of it.
- **Parsing only.** kramdown is the one dependency, and drawing stays with each app.

## Design docs

| File | Owns | Loaded |
|---|---|---|
| `README.md` | the pitch, install, how to use | — |
| `AGENTS.md` (this) | promises, invariants, the module map, conventions, commands | every turn |
| `design/decisions.md` | why this and not that — `D_` entries, FAQ-shaped | lazy |
| `design/ideas/` | not yet decided — one file per idea, `ls` is the index, deleted on graduation | transient |
| doc comments | what one symbol does and why it is shaped so | at the symbol |

Every fact lives in exactly one of these; the others link to it.

## Invariants

- **A cut needs kramdown's agreement.** A block committed on a hand-written rule may be one that later text changes. See `D_kramdown_judges_cuts`.
- **No cut inside an unclosed fence, `$$` block, HTML comment or `{::comment}`-style extension.** kramdown can't tell one there yet, so its agreement means nothing; whether a line opens one, kramdown judges.

## Module map

- `lib/streaming_markdown_parser.rb` — the parser: the cuts, the open tail, the finish and the reset.
- `lib/streaming_markdown_parser/` — the listener interface, the LLM repairs, the version.

## Conventions

- **Ruby ≥ 3.3, and no runtime dependency but kramdown and its GFM parser.** `require_relative` inside `lib/`, no Zeitwerk.
- **Errors are loud.** Misuse raises: an `append` after `finish`, a second `finish`.
- **Pre-1.0, consumed by a pinned commit:** break the API freely; each app moves its pin on purpose.
- **A new construct joins the reply in the property spec**, which checks every delta split against kramdown's parse of the whole text.

## Commands

- `bundle exec rake` — the gate: specs, rubocop, `sig/` from the YARD tags, the doc tripwires.
- CI: `.github/workflows/ci.yml` runs the gate on Ruby 3.3, 3.4 and 4.0, then fails on a `sig/` diff.
- `bundle exec rspec spec/streaming_markdown_parser_spec.rb:42` — one spec.
- `bundle lock --add-checksums` — after any Gemfile change, or CI's frozen bundle rejects the lockfile.
- `design/verify_design_tripwires.sh` — the doc-layer tripwire.

## Skills this project follows

- **Ruby:** YARD tags are the types (sord writes `sig/`, never hand-edited), rspec-core with minitest asserts, no mocks; the `ruby` skill.

## Maintenance of this file

Loaded every turn; cap 34 KB, a module's own `AGENTS.md` 10 KB. Over it, in this order:
delete what has no home — status, history, class lists, what the code already says; trim
each line to its fact plus one clause and send the explanation home — why →
`design/decisions.md`, how across symbols → `design/architecture.md`, how in one symbol →
its doc comment, what upstream does → `design/research.md`; only then a module's own
`AGENTS.md`, peripheral modules first, never the core. Never paraphrase a lazy entry into a
line here. `design/verify_design_tripwires.sh` checks the caps and the cites.
