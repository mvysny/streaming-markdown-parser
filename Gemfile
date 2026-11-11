# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Types are written once, as YARD tags; sord compiles them into the committed sig/, and
# `rake sig` fails on any tag sord cannot type. redcarpet renders the Markdown .yardopts selects.
group :development do
  gem 'rake', '~> 13.4'
  gem 'redcarpet', '~> 3.6'
  gem 'rubocop', '~> 1.92', require: false
  gem 'sord', '~> 7.1', require: false
  gem 'yard', '~> 0.9.45'

  # rubocop's parser. sord reads every bundled gem's rbi/, and parlour 9.1.2 (the latest, under
  # sord 7.1) can't parse prism 2's ("node after a sig must be a method definition").
  gem 'prism', '< 2', require: false
end

# rspec-core's structure with minitest's asserts; no rspec-expectations, no rspec-mocks.
group :test do
  gem 'minitest', '~> 6.0'
  gem 'rspec-core', '~> 3.13'
  gem 'simplecov', '~> 0.22', require: false
end
