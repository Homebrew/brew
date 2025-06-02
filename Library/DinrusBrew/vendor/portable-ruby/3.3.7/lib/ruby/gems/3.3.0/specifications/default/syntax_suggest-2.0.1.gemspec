# -*- encoding: utf-8 -*-
# stub: syntax_suggest 2.0.1 ruby lib

Gem::Specification.new do |s|
  s.name = "syntax_suggest".freeze
  s.version = "2.0.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/syntax_suggest.git", "source_code_uri" => "https://github.com/ruby/syntax_suggest.git" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["schneems".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "When you get an \"unexpected end\" in your syntax this gem helps you find it".freeze
  s.email = ["richard.schneeman+foo@gmail.com".freeze]
  s.executables = ["syntax_suggest".freeze]
  s.files = ["exe/syntax_suggest".freeze, "syntax_suggest.rb".freeze, "syntax_suggest/api.rb".freeze, "syntax_suggest/around_block_scan.rb".freeze, "syntax_suggest/block_expand.rb".freeze, "syntax_suggest/capture/before_after_keyword_ends.rb".freeze, "syntax_suggest/capture/falling_indent_lines.rb".freeze, "syntax_suggest/capture_code_context.rb".freeze, "syntax_suggest/clean_document.rb".freeze, "syntax_suggest/cli.rb".freeze, "syntax_suggest/code_block.rb".freeze, "syntax_suggest/code_frontier.rb".freeze, "syntax_suggest/code_line.rb".freeze, "syntax_suggest/code_search.rb".freeze, "syntax_suggest/core_ext.rb".freeze, "syntax_suggest/display_code_with_line_numbers.rb".freeze, "syntax_suggest/display_invalid_blocks.rb".freeze, "syntax_suggest/explain_syntax.rb".freeze, "syntax_suggest/left_right_lex_count.rb".freeze, "syntax_suggest/lex_all.rb".freeze, "syntax_suggest/lex_value.rb".freeze, "syntax_suggest/parse_blocks_from_indent_line.rb".freeze, "syntax_suggest/pathname_from_message.rb".freeze, "syntax_suggest/priority_engulf_queue.rb".freeze, "syntax_suggest/priority_queue.rb".freeze, "syntax_suggest/ripper_errors.rb".freeze, "syntax_suggest/scan_history.rb".freeze, "syntax_suggest/unvisited_lines.rb".freeze, "syntax_suggest/version.rb".freeze]
  s.homepage = "https://github.com/ruby/syntax_suggest.git".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.0.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Find syntax errors in your source in a snap".freeze
end
