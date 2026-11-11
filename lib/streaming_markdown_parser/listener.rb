# frozen_string_literal: true

class StreamingMarkdownParser
  # What a {StreamingMarkdownParser} calls. Include it and override what you use; the rest do
  # nothing. Each call gets a kramdown root, so a converter takes it as is:
  #
  #   def on_block(root) = @html << Kramdown::Converter::Html.convert(root).first
  #
  # Calls come on the thread that called {StreamingMarkdownParser#append} or
  # {StreamingMarkdownParser#finish}.
  module Listener
    # One finished top-level block, a root with that block as its only child. Final: it is never
    # called back or changed, except by {#on_reset}.
    #
    # @param root [Kramdown::Element]
    # @return [void]
    def on_block(root); end

    # The unfinished tail after the last finished block, parsed as it stands: zero or more
    # blocks, provisional. Each call replaces the one before; after the stream ends, it comes
    # empty.
    #
    # @param root [Kramdown::Element]
    # @return [void]
    def on_open(root); end

    # The final text differed from the streamed one: forget every block so far, all of them come
    # again.
    #
    # @return [void]
    def on_reset; end
  end
end
