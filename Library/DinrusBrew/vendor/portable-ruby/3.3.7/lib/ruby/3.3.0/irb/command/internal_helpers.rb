# frozen_string_literal: true

module IRB
  module Command
    # Internal use only, for default command's backward compatibility.
    module RubyArgsExtractor # :nodoc:
      def unwrap_string_literal(str)
        return if str.empty?

        sexp = Ripper.sexp(str)
        if sexp && sexp.size == 2 && sexp.last&.first&.first == :string_literal
          @irb_context.workspace.binding.eval(str).to_s
        else
          str
        end
      end

      def ruby_args(arg)
        # Use throw and catch to handle arg that includes `;`
        # For example: "1, kw: (2; 3); 4" will be parsed to [[1], { kw: 3 }]
        catch(:EXTRACT_RUBY_ARGS) do
          @irb_context.workspace.binding.eval "IRB::Command.extract_ruby_args #{arg}"
        end || [[], {}]
      end
    end
  end
end
