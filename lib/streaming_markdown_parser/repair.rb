# frozen_string_literal: true

class StreamingMarkdownParser
  # Fixes what LLMs get wrong in Markdown before kramdown parses it. Today one thing: a table
  # separator row written with typographic dashes, which kramdown won't take, so the table falls
  # apart into paragraphs of literal pipes.
  #
  #   Repair.call("| a | b |\n|—-|—-|\n| 1 | 2 |")   # => "| a | b |\n|--|--|\n| 1 | 2 |"
  #
  # Only a line made wholly of separator characters with an inner pipe is touched, so prose with
  # an em-dash and a `---` rule stay as they are.
  module Repair
    # @return [Regexp] a line of only pipes, dashes (ASCII, en, em), colons and spaces, with at
    #   least one pipe after its first character
    TABLE_SEPARATOR = /^[ \t]*\|?[ \t\-—–:]*\|[ \t\-—–:|]*$/

    module_function

    # @param source [String] Markdown
    # @return [String] the repaired Markdown
    def call(source)
      source.gsub(TABLE_SEPARATOR) { |line| line.tr('—–', '--') }
    end
  end
end
