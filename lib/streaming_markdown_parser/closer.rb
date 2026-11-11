# frozen_string_literal: true

class StreamingMarkdownParser
  # The blocks that only their closer ends: fences, `$$` math, HTML comments and kramdown's
  # extensions. Until the closer comes, kramdown reads paragraphs, so the parser takes no cut
  # inside one. It holds the open block's closer and hands it each line, getting back the closer
  # for the next:
  #
  #   closer, rest = Closer.open("$$ a = b\n", 9)   # a Closer::Math; rest is " a = b\n"
  #   closer = closer.watch(rest)                   # itself: still open
  #   closer = closer.watch("c = d $$\n")           # a Closer::MathKept: math if the next line agrees
  #   closer.watch("next\n")                        # Closer::Rewind[to: 9]: kramdown reverts it
  #
  # `watch` answers itself while the block is open, nil once it closed on that line, {PASS} when
  # the line comes after the block and is scanned like any other, or a {Rewind} when kramdown
  # reverts the block to paragraphs, so a fence inside it counts after all.
  #
  # Each closer is kramdown's own; one too loose takes a cut that the real closer then undoes.
  module Closer
    # The line is past the block; scan it as any other.
    # @return [Symbol]
    PASS = :pass

    # @return [Regexp] an extension kramdown knows, alone on its line; the self-closing
    #   `{::comment /}` opens nothing
    EXTENSION = %r{\A {0,3}\{::(comment|nomarkdown|options)(?:\s.*?)?(?<!/)\}\s*\z}

    # @return [Regexp] the line kramdown needs right after a `$$` block's closer to keep it math:
    #   blank, an IAL or `^`
    MATH_KEPT = /\A(?:#{Kramdown::Parser::Kramdown::BLOCK_BOUNDARY})/

    # @param line [String] a line where a block may start
    # @param body [Integer] where the line after it starts in the source
    # @return [Array(Object, String), nil] the closer `line` opens, if any, and the rest of `line`
    #   after the opener, for that closer's first {#watch}
    def self.open(line, body)
      if (fence = line[/\A\s*(`{3,}|~{3,})/, 1])
        [Line.new(/\A\s*#{Regexp.escape(fence[0])}{#{fence.size},}\s*\z/, nil), '']
      elsif (name = line[EXTENSION, 1])
        [Line.new(%r{\A {0,3}\{:/(?:#{name})?\}\s*\z}, "#{line.chomp}\n{:/}\n"), '']
      elsif (opener = line[/\A {0,3}<!--/])
        [Comment.new(opener), line[opener.size..]]
      elsif (opener = line[/\A {0,3}\$\$/])
        [Math.new(opener, body), line[opener.size..]]
      end
    end

    # Ends at a whole line: a fence of the same character, at least as long, or an extension's
    # `{:/name}` or `{:/}`.
    #
    # @!attribute [r] pattern
    #   @return [Regexp] the closing line
    # @!attribute [r] closed_opener
    #   @return [String, nil] the opener closed on the spot, for kramdown to confirm it opens a
    #     block; nil when no check is needed
    Line = Data.define(:pattern, :closed_opener) do
      # @param line [String]
      # @return [Object, nil] see {Closer}
      def watch(line) = pattern.match?(line) ? nil : self
    end

    # Ends at the first `-->`, mid-line too. kramdown checks nothing after it.
    #
    # @!attribute [r] opener
    #   @return [String] `<!--` and the spaces before it
    Comment = Data.define(:opener) do
      # @return [String] see {Line#closed_opener}
      def closed_opener = "#{opener}-->\n"

      # @param line [String]
      # @return [Object, nil] see {Closer}
      def watch(line) = line.include?('-->') ? nil : self
    end

    # Ends at the first `$$`, mid-line too; text after it on its line reverts the block.
    #
    # @!attribute [r] opener
    #   @return [String] `$$` and the spaces before it
    # @!attribute [r] body
    #   @return [Integer] where the line after the opener starts, to rescan from
    Math = Data.define(:opener, :body) do
      # @return [String] see {Line#closed_opener}
      def closed_opener = "#{opener}$$\n"

      # @param line [String]
      # @return [Object, nil] see {Closer}
      def watch(line)
        return self unless (at = line.index('$$'))

        line[(at + 2)..].strip.empty? ? MathKept.new(body) : Rewind.new(body)
      end
    end

    # Judges the line after a `$$` block's closer: math only if it is blank, an IAL or `^`.
    #
    # @!attribute [r] body
    #   @return [Integer] see {Math#body}
    MathKept = Data.define(:body) do
      # @param line [String]
      # @return [Object] see {Closer}
      def watch(line) = MATH_KEPT.match?(line) ? PASS : Rewind.new(body)
    end

    # kramdown reverted the block: scan again from `to`, with no block open.
    #
    # @!attribute [r] to
    #   @return [Integer] where in the source to scan from
    Rewind = Data.define(:to)
  end
end
