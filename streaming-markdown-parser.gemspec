# frozen_string_literal: true

require_relative 'lib/streaming_markdown_parser/version'

Gem::Specification.new do |spec|
  spec.name = 'streaming-markdown-parser'
  spec.version = StreamingMarkdownParser::VERSION
  spec.authors = ['Martin Vysny']
  spec.summary = 'Parses streamed Markdown, an LLM reply delta by delta, into final kramdown blocks'
  spec.homepage = 'https://github.com/mvysny/streaming-markdown-parser'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) { `git ls-files -z`.split("\x0").grep(%r{\A(lib|sig)/|\A(LICENSE|README\.md)\z}) }
  spec.require_paths = ['lib']

  spec.add_dependency 'kramdown', '~> 2.5'
  spec.add_dependency 'kramdown-parser-gfm', '~> 1.1'
end
