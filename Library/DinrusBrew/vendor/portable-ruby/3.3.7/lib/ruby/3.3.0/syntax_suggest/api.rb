# frozen_string_literal: true

require_relative "version"

require "tmpdir"
require "stringio"
require "pathname"
require "timeout"

# We need Ripper loaded for `Prism.lex_compat` even if we're using Prism
# for lexing and parsing
require "ripper"

# Prism is the new parser, replacing Ripper
#
# We need to "dual boot" both for now because syntax_suggest
# supports older rubies that do not ship with syntax suggest.
#
# We also need the ability to control loading of this library
# so we can test that both modes work correctly in CI.
if (value = ENV["SYNTAX_SUGGEST_DISABLE_PRISM"])
  warn "Skipping loading prism due to SYNTAX_SUGGEST_DISABLE_PRISM=#{value}"
else
  begin
    require "prism"
  rescue LoadError
  end
end

module SyntaxSuggest
  # Used to indicate a default value that cannot
  # be confused with another input.
  DEFAULT_VALUE = Object.new.freeze

  class Error < StandardError; end
  TIMEOUT_DEFAULT = ENV.fetch("SYNTAX_SUGGEST_TIMEOUT", 1).to_i

  # SyntaxSuggest.use_prism_parser? [Private]
  #
  # Tells us if the prism parser is available for use
  # or if we should fallback to `Ripper`
  def self.use_prism_parser?
    defined?(Prism)
  end

  # SyntaxSuggest.handle_error [Public]
  #
  # Takes a `SyntaxError` exception, uses the
  # error message to locate the file. Then the file
  # will be analyzed to find the location of the syntax
  # error and emit that location to stderr.
  #
  # Example:
  #
  #   begin
  #     require 'bad_file'
  #   rescue => e
  #     SyntaxSuggest.handle_error(e)
  #   end
  #
  # By default it will re-raise the exception unless
  # `re_raise: false`. The message output location
  # can be configured using the `io: $stderr` input.
  #
  # If a valid filename cannot be determined, the original
  # exception will be re-raised (even with
  # `re_raise: false`).
  def self.handle_error(e, re_raise: true, io: $stderr)
    unless e.is_a?(SyntaxError)
      io.puts("SyntaxSuggest: Must pass a SyntaxError, got: #{e.class}")
      raise e
    end

    file = PathnameFromMessage.new(e.message, io: io).call.name
    raise e unless file

    io.sync = true

    call(
      io: io,
      source: file.read,
      filename: file
    )

    raise e if re_raise
  end

  # SyntaxSuggest.call [Private]
  #
  # Main private interface
  def self.call(source:, filename: DEFAULT_VALUE, terminal: DEFAULT_VALUE, record_dir: DEFAULT_VALUE, timeout: TIMEOUT_DEFAULT, io: $stderr)
    search = nil
    filename = nil if filename == DEFAULT_VALUE
    Timeout.timeout(timeout) do
      record_dir ||= ENV["DEBUG"] ? "tmp" : nil
      search = CodeSearch.new(source, record_dir: record_dir).call
    end

    blocks = search.invalid_blocks
    DisplayInvalidBlocks.new(
      io: io,
      blocks: blocks,
      filename: filename,
      terminal: terminal,
      code_lines: search.code_lines
    ).call
  rescue Timeout::Error => e
    io.puts "Search timed out SYNTAX_SUGGEST_TIMEOUT=#{timeout}, run with SYNTAX_SUGGEST_DEBUG=1 for more info"
    io.puts e.backtrace.first(3).join($/)
  end

  # SyntaxSuggest.record_dir [Private]
  #
  # Used to generate a unique directory to record
  # search steps for debugging
  def self.record_dir(dir)
    time = Time.now.strftime("%Y-%m-%d-%H-%M-%s-%N")
    dir = Pathname(dir)
    dir.join(time).tap { |path|
      path.mkpath
      alias_dir = dir.join("last")
      FileUtils.rm_rf(alias_dir) if alias_dir.exist?
      FileUtils.ln_sf(time, alias_dir)
    }
  end

  # SyntaxSuggest.valid_without? [Private]
  #
  # This will tell you if the `code_lines` would be valid
  # if you removed the `without_lines`. In short it's a
  # way to detect if we've found the lines with syntax errors
  # in our document yet.
  #
  #   code_lines = [
  #     CodeLine.new(line: "def foo\n",   index: 0)
  #     CodeLine.new(line: "  def bar\n", index: 1)
  #     CodeLine.new(line: "end\n",       index: 2)
  #   ]
  #
  #   SyntaxSuggest.valid_without?(
  #     without_lines: code_lines[1],
  #     code_lines: code_lines
  #   )                                    # => true
  #
  #   SyntaxSuggest.valid?(code_lines) # => false
  def self.valid_without?(without_lines:, code_lines:)
    lines = code_lines - Array(without_lines).flatten

    if lines.empty?
      true
    else
      valid?(lines)
    end
  end

  # SyntaxSuggest.invalid? [Private]
  #
  # Opposite of `SyntaxSuggest.valid?`
  if defined?(Prism)
    def self.invalid?(source)
      source = source.join if source.is_a?(Array)
      source = source.to_s

      Prism.parse(source).failure?
    end
  else
    def self.invalid?(source)
      source = source.join if source.is_a?(Array)
      source = source.to_s

      Ripper.new(source).tap(&:parse).error?
    end
  end

  # SyntaxSuggest.valid? [Private]
  #
  # Returns truthy if a given input source is valid syntax
  #
  #   SyntaxSuggest.valid?(<<~EOM) # => true
  #     def foo
  #     end
  #   EOM
  #
  #   SyntaxSuggest.valid?(<<~EOM) # => false
  #     def foo
  #       def bar # Syntax error here
  #     end
  #   EOM
  #
  # You can also pass in an array of lines and they'll be
  # joined before evaluating
  #
  #   SyntaxSuggest.valid?(
  #     [
  #       "def foo\n",
  #       "end\n"
  #     ]
  #   ) # => true
  #
  #   SyntaxSuggest.valid?(
  #     [
  #       "def foo\n",
  #       "  def bar\n", # Syntax error here
  #       "end\n"
  #     ]
  #   ) # => false
  #
  # As an FYI the CodeLine class instances respond to `to_s`
  # so passing a CodeLine in as an object or as an array
  # will convert it to it's code representation.
  def self.valid?(source)
    !invalid?(source)
  end
end

# Integration
require_relative "cli"

# Core logic
require_relative "code_search"
require_relative "code_frontier"
require_relative "explain_syntax"
require_relative "clean_document"

# Helpers
require_relative "lex_all"
require_relative "code_line"
require_relative "code_block"
require_relative "block_expand"
require_relative "priority_queue"
require_relative "unvisited_lines"
require_relative "around_block_scan"
require_relative "priority_engulf_queue"
require_relative "pathname_from_message"
require_relative "display_invalid_blocks"
require_relative "parse_blocks_from_indent_line"
