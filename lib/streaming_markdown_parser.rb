# frozen_string_literal: true

require 'kramdown'
require 'kramdown-parser-gfm'
require_relative 'streaming_markdown_parser/version'
require_relative 'streaming_markdown_parser/listener'
require_relative 'streaming_markdown_parser/repair'
require_relative 'streaming_markdown_parser/closer'

# Parses Markdown as it streams in, an LLM reply delta by delta, into top-level blocks: each
# finished block reaches the listener once, final, and the unfinished tail is parsed again on
# every delta. Blocks are kramdown trees, so any kramdown converter renders them.
#
#   class HtmlView
#     include StreamingMarkdownParser::Listener
#
#     def initialize
#       @done = +''
#       @tail = ''
#     end
#
#     def on_block(root) = @done << Kramdown::Converter::Html.convert(root).first
#     def on_open(root) = @tail = Kramdown::Converter::Html.convert(root).first
#     def to_html = @done + @tail
#   end
#
#   parser = StreamingMarkdownParser.new(view = HtmlView.new)
#   parser.append("Hello.\n\nWor")   # on_open: "Hello.", "Wor" (the next line may continue "Hello.")
#   parser.append("ld.\n")           # on_block: "Hello.", as "World." began a new block
#                                    # on_open: "World."
#   parser.finish                    # on_block: "World."; on_open: empty
#   view.to_html                     # => "<p>Hello.</p>\n<p>World.</p>\n"
#
# A listener that wants only final output implements {Listener#on_block} alone.
#
# == Implementation details
#
# A cut between two blocks is taken only where kramdown agrees: once the first line after a
# blank line (or after a closer) is complete, the open text before it is parsed alone, the line
# alone, and both together, and the cut stands only if the blocks come out the same. So a loose
# list's next item, an indented continuation or a definition keeps the block open, with no
# Markdown rules written here.
#
# Inside an unclosed fence, `$$` math block, HTML comment or `{::comment}`-style extension there
# is no cut at all: kramdown reads paragraphs until the closer comes, and the closer would undo
# the cut. Whether a `$$`, `<!--` or extension line opens one, kramdown judges too, as a fence
# missed inside a block wrongly held open is a cut inside that fence.
#
# Per delta, the cost is one parse of the open tail, plus one check per candidate cut.
class StreamingMarkdownParser
  # @return [Hash{Symbol => Object}] GFM input, as LLMs write backtick fences and pipe tables;
  #   reply paragraphs reflow, so no hard wraps
  DEFAULT_OPTIONS = { input: 'GFM', hard_wrap: false }.freeze

  # @return [Hash{Symbol => Object}] the kramdown options every parse runs with; pass them to a
  #   converter that needs them
  attr_reader :options

  # @param listener [StreamingMarkdownParser::Listener] receives the blocks
  # @param options [Hash{Symbol => Object}] kramdown options, merged over {DEFAULT_OPTIONS}
  def initialize(listener, **options)
    @listener = listener
    @options = DEFAULT_OPTIONS.merge(options).freeze
    @source = +''
    @open_from = 0 # where the open tail starts in @source
    @scan = 0 # the first line of @source not yet scanned
    @closer = nil # the open block's Closer, nil outside one
    @boundary = false # the last scanned line ended a block, if kramdown agrees
    @finished = false
  end

  # Feeds one delta: commits every block it finishes, then re-parses the open tail. A nil or
  # empty delta does nothing.
  #
  # @param delta [String, nil]
  # @return [void]
  # @raise [RuntimeError] after {#finish}
  def append(delta)
    raise 'StreamingMarkdownParser#append after #finish' if @finished
    return if delta.nil? || delta.empty?

    @source << delta
    notify(scan, parse(@source[@open_from..]))
  end

  # Ends the stream: the open tail becomes blocks, and an empty {Listener#on_open} clears it.
  #
  # The streamed deltas may not add up to the final text (pikuri's deltas are a preview of its
  # final message). Given a different `authoritative`, the listener gets {Listener#on_reset} and
  # then every block of the authoritative text.
  #
  # @param authoritative [String, nil] the final text, nil for the deltas as they came
  # @return [void]
  # @raise [RuntimeError] if called twice
  def finish(authoritative = nil)
    raise 'StreamingMarkdownParser#finish called twice' if @finished

    @finished = true
    reset = !authoritative.nil? && authoritative != @source
    if reset
      @source = authoritative.dup
      @open_from = 0
    end
    notify(commit(@source.size), parse(''), reset:)
  end

  # @return [Boolean] true after {#finish}
  def finished? = @finished

  # @return [String] the text so far: every delta, or the authoritative text after {#finish}
  def source = @source.dup

  private

  # Walks every complete line not yet scanned, committing at each cut kramdown agrees to.
  #
  # @return [Array<Kramdown::Element>] the committed blocks, for {#notify}
  def scan
    blocks = []
    while (newline = @source.index("\n", @scan))
      start = @scan
      @scan = newline + 1
      line = @source[start...@scan]
      next if @closer && watch(line)

      if line.strip.empty?
        @boundary = true
      else
        blocks.concat(commit(start)) if @boundary && start > @open_from && clean_cut?(start, @scan)
        @boundary = false
        open_block(line, start)
      end
    end
    blocks
  end

  # @param cut [Integer] a line start in @source
  # @param line_end [Integer] the end of the line that starts at `cut`
  # @return [Boolean] true if kramdown parses the open text before `cut` and the line after it
  #   alone into the same blocks as together
  def clean_cut?(cut, line_end)
    head = @source[@open_from...cut]
    line = @source[cut...line_end]
    shape(parse(head + line)) == shape(parse(head)) + shape(parse(line))
  end

  # Ends the open text at `cut`: the open tail starts there.
  #
  # @param cut [Integer]
  # @return [Array<Kramdown::Element>] every block of the text before `cut`, each in its own root
  def commit(cut)
    root = parse(@source[@open_from...cut])
    @open_from = cut
    root.children.map do |block|
      single = Kramdown::Element.new(:root, nil, nil, root.options.dup)
      single.children << block
      single
    end
  end

  # Calls the listener, the last step of {#append} and {#finish}: the parser's state is already
  # final, so a listener that raises leaves nothing half-updated, and no block comes twice.
  #
  # @param blocks [Array<Kramdown::Element>] for {Listener#on_block}
  # @param open [Kramdown::Element] for {Listener#on_open}
  # @param reset [Boolean] true to call {Listener#on_reset} first
  # @return [void]
  def notify(blocks, open, reset: false)
    @listener.on_reset if reset
    blocks.each { |block| @listener.on_block(block) }
    @listener.on_open(open)
  end

  # @param text [String]
  # @return [Kramdown::Element] the root, its blank-line elements dropped
  def parse(text)
    root = Kramdown::Document.new(Repair.call(text), **@options).root
    root.children.reject! { |child| child.type == :blank }
    root
  end

  # @param root [Kramdown::Element]
  # @return [Array<Array>] each block as nested arrays, line numbers left out, for comparing
  def shape(root) = root.children.map { |child| element_shape(child) }

  # @param element [Kramdown::Element]
  # @return [Array]
  def element_shape(element)
    [element.type, element.value, element.attr, element.options.except(:location),
     element.children.map { |child| element_shape(child) }]
  end

  # @param start [Integer] where an opener line starts in @source
  # @param closed [String] that opener, closed on the spot
  # @return [Boolean] true if kramdown reads an opener at `start`: the open text before it, then
  #   `closed`, parse into the blocks of each alone. After a paragraph line, `$$` is inline math.
  def opens?(start, closed)
    head = @source[@open_from...start]
    types(parse(head + closed)) == types(parse(head)) + types(parse(closed))
  end

  # @param root [Kramdown::Element]
  # @return [Array<Symbol>] the type of each block
  def types(root) = root.children.map(&:type)

  # Sets {@closer} if `line` opens a block that only its closer ends, and kramdown agrees.
  #
  # @param line [String]
  # @param start [Integer] where `line` starts in @source
  # @return [void]
  def open_block(line, start)
    closer, rest = Closer.open(line, @scan)
    return unless closer
    return if closer.closed_opener && !opens?(start, closer.closed_opener)

    @closer = closer
    watch(rest)
  end

  # Hands `line` to the open block's closer and takes what it answers; see {Closer}.
  #
  # @param line [String]
  # @return [Boolean] false if `line` comes after the block, to scan like any other
  def watch(line)
    after = @closer.watch(line)
    case after
    when Closer::PASS
      @closer = nil
      return false
    when Closer::Rewind
      @scan = after.to
      @closer = nil
      @boundary = false
    else
      @boundary = true unless after.equal?(@closer)
      @closer = after
    end
    true
  end
end
