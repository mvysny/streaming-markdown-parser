# frozen_string_literal: true

# A listener that records every call as HTML, so a spec compares strings.
class Recorder
  include StreamingMarkdownParser::Listener

  # @return [Array<Array(Symbol, String)>] each call: its name and its root as HTML
  attr_reader :calls

  def initialize
    @calls = []
  end

  # @param root [Kramdown::Element]
  # @return [void]
  def on_block(root) = @calls << [:block, html(root)]

  # @param root [Kramdown::Element]
  # @return [void]
  def on_open(root) = @calls << [:open, html(root)]

  # @return [void]
  def on_reset = @calls << [:reset, '']

  # @return [Array<String>] every block so far, as HTML
  def blocks = @calls.select { |name, _| name == :block }.map(&:last)

  # @return [String, nil] the last open tail, as HTML
  def open = @calls.reverse.find { |name, _| name == :open }&.last

  # @return [Array<Array(Symbol, String)>] the calls since the last {#take}
  def take
    taken = @calls
    @calls = []
    taken
  end

  private

  def html(root) = Kramdown::Converter::Html.convert(root).first
end

# @param markdown [String]
# @return [Array<String>] each top-level block of the one-shot parse of the whole text, as HTML
def whole_blocks(markdown)
  root = StreamingMarkdownParser.parse(markdown)
  root.children.map do |block|
    single = Kramdown::Element.new(:root, nil, nil, root.options)
    single.children << block
    Kramdown::Converter::Html.convert(single).first
  end
end
