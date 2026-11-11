# frozen_string_literal: true

RSpec.describe StreamingMarkdownParser do
  let(:recorder) { Recorder.new }
  let(:parser) { described_class.new(recorder) }

  # An LLM reply with each construct whose end is only known later.
  reply = <<~MD
    # Keeping avocados

    Ripe ones go to the **fridge**; unripe ones stay out.

    See [the guide][g] on ripening.

    [g]: https://example.com/guide

    [s]: https://example.com/store
    Buy them at [the store][s].

    Ripeness takes days[^n].

    [^n]: It yields to a gentle squeeze.

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

    > ```
    > quoted code
    >
    > after a quoted blank
    > ```

    Setext heading
    ==============

    - outer

      - inner, loose

      - inner again

    - outer again

        indented code

        after a blank

    <div>

    raw HTML, blank lines and all

    </div>

    $$
    a = b

    c = d $$

    $$ one line $$

    $$
    reverted by the text after its closer

    ```
    code $$ tail

    more
    ```

    <!--

    hidden --> shown

    {::comment}

    hidden

    {:/comment}

    {::nomarkdown}
    <b>raw</b>

    {:/}

    {::comment /}

    ~~~
    unclosed until the end
  MD

  # @param text [String]
  # @param random [Random]
  # @return [Array<String>] `text` in chunks of 1 to 80 characters: a chunk ends mid-line,
  #   mid-fence or mid-list, and the next may finish several lines at once
  def random_chunks(text, random)
    chunks = []
    at = 0
    while at < text.size
      size = random.rand(1..80)
      chunks << text[at, size]
      at += size
    end
    chunks
  end

  describe 'whatever the deltas' do
    {
      'one delta' => ->(text) { [text] },
      'a character each' => :chars.to_proc,
      'a line each' => :lines.to_proc,
      'cut right before newlines' => ->(text) { text.split(/(?=\n)/) }
    }.each do |name, split|
      it "ends in kramdown's blocks of the whole text: #{name}" do
        split.call(reply).each { parser.append(_1) }
        parser.finish
        assert_equal whole_blocks(reply), recorder.blocks
      end
    end

    it "ends in kramdown's blocks of the whole text: random chunks" do
      seed = Random.new_seed
      random = Random.new(seed)
      want = whole_blocks(reply)
      20.times do
        recorder = Recorder.new
        parser = described_class.new(recorder)
        random_chunks(reply, random).each { parser.append(_1) }
        parser.finish
        assert_equal want, recorder.blocks, "seed #{seed}"
      end
    end

    it "ends in kramdown's blocks of the whole text: CRLF line ends" do
      crlf = reply.gsub("\n", "\r\n")
      crlf.chars.each { parser.append(_1) }
      parser.finish
      assert_equal whole_blocks(crlf), recorder.blocks
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

    it 'never cuts inside a $$ block, blank lines and all' do
      parser.append("$$\na = b\n\nc = d\n")
      assert_empty recorder.blocks
      parser.append("$$\n\nAfter.\n")
      assert_equal 1, recorder.blocks.size
      assert_includes recorder.blocks.first, 'a = b'
    end

    it 'opens no $$ block where kramdown reads inline math, so a fence inside still counts' do
      text = "para\n$$\n\n```\nx\n\ny $$\n\nz\n```\n"
      text.each_char { parser.append(_1) }
      parser.finish
      assert_equal whole_blocks(text), recorder.blocks
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

    {
      'defined a block later' => "See [the docs][1].\n\nMore.\n\n[1]: https://example.com\n",
      'reused a block after its definition' => "[1]: https://example.com\nSee [it][1].\n\nMore.\n\nSee [the docs][1].\n"
    }.each do |name, text|
      it "leaves a reference literal for good, which .parse resolves: #{name}" do
        text.each_char { parser.append(_1) }
        parser.finish
        assert_includes recorder.blocks, "<p>See [the docs][1].</p>\n"
        assert_includes whole_blocks(text), "<p>See <a href=\"https://example.com\">the docs</a>.</p>\n"
      end
    end

    it 'raises after #finish' do
      parser.finish
      err = assert_raises(RuntimeError) { parser.append('x') }
      assert_includes err.message, 'after #finish'
    end

    it 'never sends a block twice, though the listener raised mid-commit' do
      raising = Class.new(Recorder) do
        attr_accessor :boom

        def on_block(root)
          super
          raise 'boom' if boom
        end
      end.new
      parser = described_class.new(raising)
      parser.append("p\n# H\n\n")
      raising.boom = true
      assert_raises(RuntimeError) { parser.append("q\n") }
      raising.boom = false
      parser.append("\n")
      parser.finish
      assert_equal ["<p>p</p>\n", "<p>q</p>\n"], raising.blocks
    end
  end

  describe '.parse' do
    it 'repairs the text and drops blank-line elements' do
      root = described_class.parse("Hi.\n\n| a |\n|—-|\n| 1 |\n")
      assert_equal %i[p table], root.children.map(&:type)
    end

    it 'merges the options over the defaults' do
      root = described_class.parse("a\nb\n", hard_wrap: true)
      assert_equal "<p>a<br />\nb</p>\n", Kramdown::Converter::Html.convert(root).first
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

    it 'given a whole text and no deltas, sends its blocks with no reset' do
      parser.finish("Hello.\n\nWorld.\n")
      assert_equal [[:block, "<p>Hello.</p>\n"], [:block, "<p>World.</p>\n"], [:open, '']], recorder.take
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
