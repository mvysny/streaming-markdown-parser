# frozen_string_literal: true

RSpec.describe StreamingMarkdownParser::Repair do
  it 'turns typographic dashes in a table separator into hyphens' do
    assert_equal "| a | b |\n|--|:-:|\n| 1 | 2 |", described_class.call("| a | b |\n|—-|:–:|\n| 1 | 2 |")
  end

  it 'leaves prose with an em-dash alone' do
    assert_equal "Fresh — or frozen | both\n", described_class.call("Fresh — or frozen | both\n")
  end

  it 'leaves a horizontal rule alone' do
    assert_equal "—-\n", described_class.call("—-\n")
  end
end
