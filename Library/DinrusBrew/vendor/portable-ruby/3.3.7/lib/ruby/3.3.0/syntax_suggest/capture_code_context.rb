# frozen_string_literal: true

module SyntaxSuggest
  module Capture
  end
end

require_relative "capture/falling_indent_lines"
require_relative "capture/before_after_keyword_ends"

module SyntaxSuggest
  # Turns a "invalid block(s)" into useful context
  #
  # There are three main phases in the algorithm:
  #
  # 1. Sanitize/format input source
  # 2. Search for invalid blocks
  # 3. Format invalid blocks into something meaninful
  #
  # This class handles the third part.
  #
  # The algorithm is very good at capturing all of a syntax
  # error in a single block in number 2, however the results
  # can contain ambiguities. Humans are good at pattern matching
  # and filtering and can mentally remove extraneous data, but
  # they can't add extra data that's not present.
  #
  # In the case of known ambiguious cases, this class adds context
  # back to the ambiguity so the programmer has full information.
  #
  # Beyond handling these ambiguities, it also captures surrounding
  # code context information:
  #
  #   puts block.to_s # => "def bark"
  #
  #   context = CaptureCodeContext.new(
  #     blocks: block,
  #     code_lines: code_lines
  #   )
  #
  #   lines = context.call.map(&:original)
  #   puts lines.join
  #   # =>
  #     class Dog
  #       def bark
  #     end
  #
  class CaptureCodeContext
    attr_reader :code_lines

    def initialize(blocks:, code_lines:)
      @blocks = Array(blocks)
      @code_lines = code_lines
      @visible_lines = @blocks.map(&:visible_lines).flatten
      @lines_to_output = @visible_lines.dup
    end

    def call
      @blocks.each do |block|
        capture_first_kw_end_same_indent(block)
        capture_last_end_same_indent(block)
        capture_before_after_kws(block)
        capture_falling_indent(block)
      end

      sorted_lines
    end

    def sorted_lines
      @lines_to_output.select!(&:not_empty?)
      @lines_to_output.uniq!
      @lines_to_output.sort!

      @lines_to_output
    end

    # Shows the context around code provided by "falling" indentation
    #
    # Converts:
    #
    #       it "foo" do
    #
    # into:
    #
    #   class OH
    #     def hello
    #       it "foo" do
    #     end
    #   end
    #
    def capture_falling_indent(block)
      Capture::FallingIndentLines.new(
        block: block,
        code_lines: @code_lines
      ).call do |line|
        @lines_to_output << line
      end
    end

    # Shows surrounding kw/end pairs
    #
    # The purpose of showing these extra pairs is due to cases
    # of ambiguity when only one visible line is matched.
    #
    # For example:
    #
    #     1  class Dog
    #     2    def bark
    #     4    def eat
    #     5    end
    #     6  end
    #
    # In this case either line 2 could be missing an `end` or
    # line 4 was an extra line added by mistake (it happens).
    #
    # When we detect the above problem it shows the issue
    # as only being on line 2
    #
    #     2    def bark
    #
    # Showing "neighbor" keyword pairs gives extra context:
    #
    #     2    def bark
    #     4    def eat
    #     5    end
    #
    def capture_before_after_kws(block)
      return unless block.visible_lines.count == 1

      around_lines = Capture::BeforeAfterKeywordEnds.new(
        code_lines: @code_lines,
        block: block
      ).call

      around_lines -= block.lines

      @lines_to_output.concat(around_lines)
    end

    # When there is an invalid block with a keyword
    # missing an end right before another end,
    # it is unclear where which keyword is missing the
    # end
    #
    # Take this example:
    #
    #   class Dog       # 1
    #     def bark      # 2
    #       puts "woof" # 3
    #   end             # 4
    #
    # However due to https://github.com/ruby/syntax_suggest/issues/32
    # the problem line will be identified as:
    #
    #  > class Dog       # 1
    #
    # Because lines 2, 3, and 4 are technically valid code and are expanded
    # first, deemed valid, and hidden. We need to un-hide the matching end
    # line 4. Also work backwards and if there's a mis-matched keyword, show it
    # too
    def capture_last_end_same_indent(block)
      return if block.visible_lines.length != 1
      return unless block.visible_lines.first.is_kw?

      visible_line = block.visible_lines.first
      lines = @code_lines[visible_line.index..block.lines.last.index]

      # Find first end with same indent
      # (this would return line 4)
      #
      #   end             # 4
      matching_end = lines.detect { |line| line.indent == block.current_indent && line.is_end? }
      return unless matching_end

      @lines_to_output << matching_end

      # Work backwards from the end to
      # see if there are mis-matched
      # keyword/end pairs
      #
      # Return the first mis-matched keyword
      # this would find line 2
      #
      #     def bark      # 2
      #       puts "woof" # 3
      #   end             # 4
      end_count = 0
      kw_count = 0
      kw_line = @code_lines[visible_line.index..matching_end.index].reverse.detect do |line|
        end_count += 1 if line.is_end?
        kw_count += 1 if line.is_kw?

        !kw_count.zero? && kw_count >= end_count
      end
      return unless kw_line
      @lines_to_output << kw_line
    end

    # The logical inverse of `capture_last_end_same_indent`
    #
    # When there is an invalid block with an `end`
    # missing a keyword right after another `end`,
    # it is unclear where which end is missing the
    # keyword.
    #
    # Take this example:
    #
    #   class Dog       # 1
    #       puts "woof" # 2
    #     end           # 3
    #   end             # 4
    #
    # the problem line will be identified as:
    #
    #  > end            # 4
    #
    # This happens because lines 1, 2, and 3 are technically valid code and are expanded
    # first, deemed valid, and hidden. We need to un-hide the matching keyword on
    # line 1. Also work backwards and if there's a mis-matched end, show it
    # too
    def capture_first_kw_end_same_indent(block)
      return if block.visible_lines.length != 1
      return unless block.visible_lines.first.is_end?

      visible_line = block.visible_lines.first
      lines = @code_lines[block.lines.first.index..visible_line.index]
      matching_kw = lines.reverse.detect { |line| line.indent == block.current_indent && line.is_kw? }
      return unless matching_kw

      @lines_to_output << matching_kw

      kw_count = 0
      end_count = 0
      orphan_end = @code_lines[matching_kw.index..visible_line.index].detect do |line|
        kw_count += 1 if line.is_kw?
        end_count += 1 if line.is_end?

        end_count >= kw_count
      end

      return unless orphan_end
      @lines_to_output << orphan_end
    end
  end
end
