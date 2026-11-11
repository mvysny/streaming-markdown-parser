# frozen_string_literal: true

RSpec.describe StreamingMarkdownParser do
  let(:recorder) { Recorder.new }
  let(:parser) { described_class.new(recorder) }

  # An LLM reply with each construct whose end is only known later.
  reply = <<~MD
    # Keeping avocados

    Ripe ones go to the **fridge**; unripe ones stay out.

    - loose list, first item

    - second item, with a continuation:

      still the second item

    1. step one

       ```sh
       ripen --paper-bag

       done
       ```

    2. step two

    Term
    : its definition

    | Where | Days |
    |—-|—-|
    | fridge | 3 |

    > a quote

    ~~~
    unclosed until the end
  MD

  describe 'whatever the deltas' do
    {
      'one delta' => ->(text) { [text] },
      'a character each' => :chars.to_proc,
      'a line each' => :lines.to_proc,
      'random chunks' => ->(text) { text.chars.each_slice(7).map(&:join) },
      'cut right before newlines' => ->(text) { text.split(/(?=\n)/) }
    }.each do |name, split|
      it "ends in kramdown's blocks of the whole text: #{name}" do
        split.call(reply).each { parser.append(_1) }
        parser.finish
        assert_equal whole_blocks(reply), recorder.blocks
      end
    end
  end

  describe '#append' do
    it 'commits a block once the line after it starts a new one' do
      parser.append("Hello.\n\nWor")
      assert_equal [[:open, "<p>Hello.</p>\n<p>Wor</p>\n"]], recorder.take
      parser.append("ld.\n")
      assert_equal [[:block, "<p>Hello.</p>\n"], [:open, "<p>World.</p>\n"]], recorder.take
    end

    it 'keeps a loose list open while items follow' do
      parser.append("- a\n\n- b\n\n- c\n")
      assert_empty recorder.blocks
      parser.append("\nAfter.\n")
      assert_equal 1, recorder.blocks.size
      assert_includes recorder.blocks.first, '<li>'
      assert_equal "<p>After.</p>\n", recorder.open
    end

    it 'never cuts inside a fence, blank lines and all' do
      parser.append("```\na\n\nb\n\nc\n")
      assert_empty recorder.blocks
      parser.append("```\nAfter.\n")
      assert_equal ["<pre><code>a\n\nb\n\nc\n</code></pre>\n"], recorder.blocks
    end

    it 'takes only a closing fence of the same character, at least as long' do
      parser.append("````\n~~~~\n```\n````\nAfter.\n")
      assert_equal ["<pre><code>~~~~\n```\n</code></pre>\n"], recorder.blocks
    end

    it 'commits the blocks before an interrupted list, not the list' do
      parser.append("Steps:\n\n1. one\n\n2. two\n")
      assert_equal ["<p>Steps:</p>\n"], recorder.blocks
    end

    it 'does nothing on an empty or nil delta' do
      parser.append('')
      parser.append(nil)
      assert_empty recorder.calls
    end

    it 'repairs a table separator written with em-dashes' do
      parser.append("| a | b |\n|—-|—-|\n| 1 | 2 |\n\nAfter.\n")
      assert_includes recorder.blocks.first, '<table>'
    end

    it 'raises after #finish' do
      parser.finish
      err = assert_raises(RuntimeError) { parser.append('x') }
      assert_includes err.message, 'after #finish'
    end
  end

  describe '#finish' do
    it 'commits the open tail and clears it' do
      parser.append("Hello.\n\nWorld.")
      recorder.take
      parser.finish
      assert_equal [[:block, "<p>Hello.</p>\n"], [:block, "<p>World.</p>\n"], [:open, '']], recorder.take
    end

    it 'given the streamed text, adds no reset' do
      parser.append('Hello.')
      parser.finish('Hello.')
      refute(recorder.calls.any? { |name, _| name == :reset })
      assert_equal ["<p>Hello.</p>\n"], recorder.blocks
    end

    it 'given another text, resets and sends every block of it' do
      parser.append("Hello.\n\nWorld.\n")
      recorder.take
      parser.finish("Hello.\n\nEarth.\n")
      assert_equal [[:reset, ''], [:block, "<p>Hello.</p>\n"], [:block, "<p>Earth.</p>\n"], [:open, '']],
                   recorder.take
      assert_equal "Hello.\n\nEarth.\n", parser.source
    end

    it 'raises if called twice' do
      parser.finish
      assert_raises(RuntimeError) { parser.finish }
      assert parser.finished?
    end
  end

  it 'renders through any kramdown converter, as the class doc shows' do
    view = Class.new do
      include StreamingMarkdownParser::Listener

      def initialize
        @done = +''
        @tail = ''
      end

      def on_block(root) = @done << Kramdown::Converter::Html.convert(root).first
      def on_open(root) = @tail = Kramdown::Converter::Html.convert(root).first
      def to_html = @done + @tail
    end.new
    parser = described_class.new(view)
    parser.append("Hello.\n\nWor")
    parser.append("ld.\n")
    parser.finish
    assert_equal "<p>Hello.</p>\n<p>World.</p>\n", view.to_html
  end
end
