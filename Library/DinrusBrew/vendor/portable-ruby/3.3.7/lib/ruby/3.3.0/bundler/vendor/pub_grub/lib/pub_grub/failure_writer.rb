module Bundler::PubGrub
  class FailureWriter
    def initialize(root)
      @root = root

      # { Incompatibility => Integer }
      @derivations = {}

      # [ [ String, Integer or nil ] ]
      @lines = []

      # { Incompatibility => Integer }
      @line_numbers = {}

      count_derivations(root)
    end

    def write
      return @root.to_s unless @root.conflict?

      visit(@root)

      padding = @line_numbers.empty? ? 0 : "(#{@line_numbers.values.last}) ".length

      @lines.map do |message, number|
        next "" if message.empty?

        lead = number ? "(#{number}) " : ""
        lead = lead.ljust(padding)
        message = message.gsub("\n", "\n" + " " * (padding + 2))
        "#{lead}#{message}"
      end.join("\n")
    end

    private

    def write_line(incompatibility, message, numbered:)
      if numbered
        number = @line_numbers.length + 1
        @line_numbers[incompatibility] = number
      end

      @lines << [message, number]
    end

    def visit(incompatibility, conclusion: false)
      raise unless incompatibility.conflict?

      numbered = conclusion || @derivations[incompatibility] > 1;
      conjunction = conclusion || incompatibility == @root ? "So," : "And"

      cause = incompatibility.cause

      if cause.conflict.conflict? && cause.other.conflict?
        conflict_line = @line_numbers[cause.conflict]
        other_line = @line_numbers[cause.other]

        if conflict_line && other_line
          write_line(
            incompatibility,
            "Because #{cause.conflict} (#{conflict_line})\nand #{cause.other} (#{other_line}),\n#{incompatibility}.",
            numbered: numbered
          )
        elsif conflict_line || other_line
          with_line    = conflict_line ? cause.conflict : cause.other
          without_line = conflict_line ? cause.other : cause.conflict
          line = @line_numbers[with_line]

          visit(without_line);
          write_line(
            incompatibility,
            "#{conjunction} because #{with_line} (#{line}),\n#{incompatibility}.",
            numbered: numbered
          )
        else
          single_line_conflict = single_line?(cause.conflict.cause)
          single_line_other    = single_line?(cause.other.cause)

          if single_line_conflict || single_line_other
            first  = single_line_other ? cause.conflict : cause.other
            second = single_line_other ? cause.other : cause.conflict
            visit(first)
            visit(second)
            write_line(
              incompatibility,
              "Thus, #{incompatibility}.",
              numbered: numbered
            )
          else
            visit(cause.conflict, conclusion: true)
            @lines << ["", nil]
            visit(cause.other)

            write_line(
              incompatibility,
              "#{conjunction} because #{cause.conflict} (#{@line_numbers[cause.conflict]}),\n#{incompatibility}.",
              numbered: numbered
            )
          end
        end
      elsif cause.conflict.conflict? || cause.other.conflict?
        derived = cause.conflict.conflict? ? cause.conflict : cause.other
        ext     = cause.conflict.conflict? ? cause.other : cause.conflict

        derived_line = @line_numbers[derived]
        if derived_line
          write_line(
            incompatibility,
            "Because #{ext}\nand #{derived} (#{derived_line}),\n#{incompatibility}.",
            numbered: numbered
          )
        elsif collapsible?(derived)
          derived_cause = derived.cause
          if derived_cause.conflict.conflict?
            collapsed_derived = derived_cause.conflict
            collapsed_ext = derived_cause.other
          else
            collapsed_derived = derived_cause.other
            collapsed_ext = derived_cause.conflict
          end

          visit(collapsed_derived)

          write_line(
            incompatibility,
            "#{conjunction} because #{collapsed_ext}\nand #{ext},\n#{incompatibility}.",
            numbered: numbered
          )
        else
          visit(derived)
          write_line(
            incompatibility,
            "#{conjunction} because #{ext},\n#{incompatibility}.",
            numbered: numbered
          )
        end
      else
        write_line(
          incompatibility,
          "Because #{cause.conflict}\nand #{cause.other},\n#{incompatibility}.",
          numbered: numbered
        )
      end
    end

    def single_line?(cause)
      !cause.conflict.conflict? && !cause.other.conflict?
    end

    def collapsible?(incompatibility)
      return false if @derivations[incompatibility] > 1

      cause = incompatibility.cause
      # If incompatibility is derived from two derived incompatibilities,
      # there are too many transitive causes to display concisely.
      return false if cause.conflict.conflict? && cause.other.conflict?

      # If incompatibility is derived from two external incompatibilities, it
      # tends to be confusing to collapse it.
      return false unless cause.conflict.conflict? || cause.other.conflict?

      # If incompatibility's internal cause is numbered, collapsing it would
      # get too noisy.
      complex = cause.conflict.conflict? ? cause.conflict : cause.other

      !@line_numbers.has_key?(complex)
    end

    def count_derivations(incompatibility)
      if @derivations.has_key?(incompatibility)
        @derivations[incompatibility] += 1
      else
        @derivations[incompatibility] = 1
        if incompatibility.conflict?
          cause = incompatibility.cause
          count_derivations(cause.conflict)
          count_derivations(cause.other)
        end
      end
    end
  end
end
