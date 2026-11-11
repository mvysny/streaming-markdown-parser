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
gets a kramdown root, which any converter takes as it is:

```ruby
class HtmlView
  include StreamingMarkdownParser::Listener

  def initialize
    @done = +''
    @tail = ''
  end

  def on_block(root) = @done << Kramdown::Converter::Html.convert(root).first
  def on_open(root) = @tail = Kramdown::Converter::Html.convert(root).first
  def to_html = @done + @tail
end

parser = StreamingMarkdownParser.new(view = HtmlView.new)
parser.append("Hello.\n\nWor")   # on_open: "Hello.", "Wor" (the next line may continue "Hello.")
parser.append("ld.\n")           # on_block: "Hello."; on_open: "World."
parser.finish                    # on_block: "World."; on_open: empty
view.to_html                     # => "<p>Hello.</p>\n<p>World.</p>\n"
```

| Call | When | Final? |
|---|---|---|
| `on_block(root)` | a top-level block is finished: a paragraph, a list, a table, a fence | yes, sent once |
| `on_open(root)` | after every delta: the tail after the last finished block | no, each replaces the last |
| `on_reset` | `finish(text)` got a final text that differs from the deltas | forget all blocks; they come again |

A listener that wants only final output implements `on_block` alone.

## When is a block finished?

When the next one has begun, as kramdown sees it. After a blank line, or a closing fence, the
first complete line is parsed with the open text before it, and alone. Only if the blocks come
out the same is the cut taken, so a loose list, an indented continuation or a fenced block inside
a list item stays open until it truly ends. However the reply is cut into deltas, the blocks equal
kramdown's parse of the whole text.

Before parsing, `StreamingMarkdownParser::Repair` fixes what LLMs get wrong; today, a table
separator written with em-dashes (`|—-|`), which kramdown would not take for a table.

## License

MIT
