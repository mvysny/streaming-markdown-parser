# streaming-markdown-parser

Parses Markdown as it streams in, an LLM's reply delta by delta, into top-level kramdown blocks.
Each finished block reaches your listener once and never changes; the unfinished tail comes
again, provisional, on every delta. It draws nothing: the terminal, the web page or the window
keeps its own kramdown converter.

## Install

Not on RubyGems; depend on the git repository, and let `Gemfile.lock` pin the commit:

```ruby
gem 'streaming-markdown-parser', git: 'https://github.com/mvysny/streaming-markdown-parser.git',
                                 branch: 'master', require: 'streaming_markdown_parser'
```

Ruby 3.3 or newer; the only dependencies are `kramdown` and `kramdown-parser-gfm`.

## Use

A listener includes `StreamingMarkdownParser::Listener` and overrides what it needs. Every call
gets a kramdown root, which any converter takes (but see *Rendering block by block*):

```ruby
class HtmlView
  include StreamingMarkdownParser::Listener

  def initialize
    @done = +''
    @tail = ''
  end

  def on_block(root) = @done << Kramdown::Converter::Html.convert(root).first
  def on_open(root) = @tail = Kramdown::Converter::Html.convert(root).first
  def on_reset = @done.clear
  def to_html = @done + @tail
end

parser = StreamingMarkdownParser.new(view = HtmlView.new)
parser.append("Hello.\n\nWor")   # on_open: "Hello.", "Wor" (the next line may continue "Hello.")
parser.append("ld.\n")           # on_block: "Hello."; on_open: "World."
parser.finish                    # on_block: "World."; on_open: empty (no text given: no on_reset)
view.to_html                     # => "<p>Hello.</p>\n<p>World.</p>\n"
```

| Call | When | Final? |
|---|---|---|
| `on_block(root)` | a top-level block is finished: a paragraph, a list, a table, a fence | yes, sent once |
| `on_open(root)` | after every delta: the tail after the last finished block | no, each replaces the last |
| `on_reset` | `finish(text)` got a final text that differs from the deltas | drop every block so far; the final text's blocks follow, from the first |

A listener that wants only final output implements `on_block` alone.

One parser per reply: after `finish`, `append` and another `finish` raise. Take a new parser for
the next reply; the listener may stay.

A block is one top-level element of the reply: a paragraph, a heading, a table, a fence, a rule,
or a whole list or blockquote with everything inside it. In prose a block *is* a paragraph: each
`on_block` is one finished paragraph, and the next one is in `on_open`.

Once the stream ends, render the reply once more from its whole text, as only there does every
reference link and footnote resolve (see *When is a block finished?*). The same goes for a reply
that arrives whole (a non-streaming provider, a replayed transcript):

```ruby
root = StreamingMarkdownParser.parse(text)          # one root, for one converter call
StreamingMarkdownParser.new(view).finish(text)      # or the same calls a stream makes, no on_reset
```

Take a fresh parser for that: the streaming one's `finish(text)`, given the text it streamed,
keeps the blocks it sent. And convert `parse`'s root in one call, or each block gets its own
footnotes list.

### When the final text differs

Some providers stream a preview, and the final message they hand over at the end is not quite
the deltas added up. Pass it to `finish(text)`:

- **The same text as the deltas:** an ordinary finish. The open tail becomes blocks, and the
  blocks already sent stay.
- **A different text:** the change may be anywhere, even in the first block, so no block sent
  so far can be trusted. The parser starts over, all within that `finish` call: `on_reset`,
  then `on_block` for every block of the final text from the first, then an empty `on_open`.
  The listener drops what it built on `on_reset` and builds the reply again from the calls that
  follow, as `HtmlView` above does.

`finish` with no text takes the deltas as they came and never resets. Neither does a parser
that got no delta before `finish(text)`, as there is nothing to drop.

### Rendering block by block

Two things a whole-document render gets for free are the listener's job:

- **Spacing between blocks.** Blocks stack vertically, each below the last at full width, never
  side by side, and with no separator but a rule the reply itself has. The source's blank lines
  are dropped, so the listener puts its own spacing between them. HTML needs none, as `<p>`
  brings its own margin; a terminal or plain-text converter does.
- **State from block to block.** Each root is converted alone, so a converter that remembers
  something across blocks needs the listener to carry it: the indent under the last header,
  footnote numbers. Such an app takes a whole reply through `new(listener).finish(text)` too, not
  `.parse`, so a reply renders alike however it arrived.

## When is a block finished?

When the next one has begun, as kramdown sees it. After a blank line, or a closing fence, the
first complete line is parsed with the open text before it, and alone. Only if the blocks come
out the same is the cut taken, so a loose list, an indented continuation or a fenced block inside
a list item stays open until it truly ends. However the reply is cut into deltas, the blocks equal
kramdown's parse of the whole text, references aside.

A reference link (`[the docs][1]`) or footnote (`[^a]`) resolves against a definition anywhere in
the text, but each side of a cut is parsed alone. A definition right before or after the block
stays with it; one a block or more away leaves the reference literal, and the definition shows as
nothing. A model that cites its sources at the end streams `[the docs][1]` and no URL. The parser
never takes such a block back: the render of the whole reply at the end resolves it.

Before parsing, `StreamingMarkdownParser::Repair` fixes what LLMs get wrong; today, a table
separator written with em-dashes (`|—-|`), which kramdown would not take for a table.

## License

MIT
