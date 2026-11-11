# frozen_string_literal: true

require 'kramdown'
require 'kramdown-parser-gfm'
require_relative 'streaming_markdown_parser/version'
require_relative 'streaming_markdown_parser/listener'
require_relative 'streaming_markdown_parser/repair'

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
# blank line (or after a closing fence) is complete, the open text before it is parsed alone, the
# line alone, and both together, and the cut stands only if the blocks come out the same. So a
# loose list's next item, an indented continuation or a definition keeps the block open, with no
# Markdown rules written here. Inside an unclosed fence there is no cut at all: kramdown can't yet
# tell it is a fence.
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
    @fence = nil # the open fence's [char, length], or nil outside one
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
    scan
    @listener.on_open(parse(@source[@open_from..]))
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
    if authoritative && authoritative != @source
      @listener.on_reset
      @source = authoritative.dup
      @open_from = 0
    end
    commit(@source.size)
    @listener.on_open(parse(''))
  end

  # @return [Boolean] true after {#finish}
  def finished? = @finished

  # @return [String] the text so far: every delta, or the authoritative text after {#finish}
  def source = @source.dup

  private

  # Walks every complete line not yet scanned, committing at each cut kramdown agrees to.
  #
  # @return [void]
  def scan
    while (newline = @source.index("\n", @scan))
      start = @scan
      @scan = newline + 1
      line = @source[start...@scan]
      if @fence
        @boundary = closes_fence?(line)
        @fence = nil if @boundary
      elsif line.strip.empty?
        @boundary = true
      else
        commit(start) if @boundary && start > @open_from && clean_cut?(start, @scan)
        @boundary = false
        @fence = opened_fence(line)
      end
    end
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

  # Hands every block of the open text up to `cut` to the listener; the open tail starts there.
  #
  # @param cut [Integer]
  # @return [void]
  def commit(cut)
    root = parse(@source[@open_from...cut])
    root.children.each do |block|
      single = Kramdown::Element.new(:root, nil, nil, root.options.dup)
      single.children << block
      @listener.on_block(single)
    end
    @open_from = cut
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

  # @param line [String]
  # @return [Array(String, Integer), nil] the fence's character and length if `line` opens one
  def opened_fence(line)
    marker = line[/\A\s*(`{3,}|~{3,})/, 1]
    marker && [marker[0], marker.size]
  end

  # @param line [String]
  # @return [Boolean] true if `line` closes the open fence: the same character, at least as many
  #   of it, and nothing else
  def closes_fence?(line)
    marker = line[/\A\s*(`{3,}|~{3,})\s*\z/, 1]
    !marker.nil? && marker[0] == @fence[0] && marker.size >= @fence[1]
  end
end
