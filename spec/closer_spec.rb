# frozen_string_literal: true

# Each closer against kramdown's own closing rules; the property spec checks them against
# kramdown's parse.
RSpec.describe StreamingMarkdownParser::Closer do
  # @param lines [Array<String>] an opener line, then the lines after it
  # @return [Object, nil] what the closer answers to the last line
  def feed(*lines)
    closer, rest = described_class.open(lines.first, 100)
    lines.drop(1).reduce(closer.watch(rest)) { |now, line| now.watch(line) }
  end

  it 'opens nothing on a paragraph line or a self-closing extension' do
    assert_nil described_class.open("text\n", 0)
    assert_nil described_class.open("{::comment /}\n", 0)
    assert_nil described_class.open("{::unknown}\n", 0)
  end

  describe 'a fence' do
    it 'closes at the same character, at least as long, alone on its line' do
      fence = described_class.open("````ruby\n", 0).first
      assert_same fence, fence.watch("```\n")
      assert_same fence, fence.watch("~~~~\n")
      assert_same fence, fence.watch("```` x\n")
      assert_nil fence.watch("`````\n")
    end
  end

  describe 'an extension' do
    it 'closes at its own name or the short closer, alone on its line' do
      assert_nil feed("{::comment}\n", "x\n", "{:/comment}\n")
      assert_nil feed("{::nomarkdown type=\"html\"}\n", "{:/}\n")
    end

    it 'stays open at a closer mid-line, with text after it, or of another name' do
      ["x {:/comment}\n", "{:/comment} x\n", "{:/nomarkdown}\n"].each do |line|
        assert_kind_of described_class::Line, feed("{::comment}\n", line)
      end
    end
  end

  describe 'an HTML comment' do
    it 'closes at the first -->, mid-line and on its opener line too' do
      assert_nil feed("<!-- x --> shown\n")
      assert_nil feed("<!--\n", "\n", "hidden --> shown\n")
    end
  end

  describe 'a $$ block' do
    it 'closes at the first $$, on its opener line too, then judges the line after' do
      assert_kind_of described_class::MathKept, feed("$$ a = b $$\n")
      assert_equal described_class::PASS, feed("$$\n", "a\n", "\n", "c = d $$\n", "\n")
      assert_equal described_class::PASS, feed("$$\n", "a\n", "$$\n", "{: .x}\n")
    end

    it 'rewinds to the line after its opener when kramdown reverts it' do
      assert_equal described_class::Rewind.new(100), feed("$$\n", "a $$ tail\n")
      assert_equal described_class::Rewind.new(100), feed("$$\n", "a\n", "$$\n", "next\n")
    end
  end
end
