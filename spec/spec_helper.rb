# frozen_string_literal: true

# simplecov first, so loading the library is measured.
require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
end

require_relative '../lib/streaming_markdown_parser'
Dir[File.join(__dir__, 'support', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :minitest
  config.disable_monkey_patching!
end
