# typed: true # This cannot be `# typed: strict` due to the use of `undef`.
# frozen_string_literal: true

module Homebrew
  module CLI
    class Parser
      undef set_default_options
      undef validate_options

      def set_default_options
        @args["formula?"] = true if @args.respond_to?(:formula?)
      end

      def validate_options
        return unless @args.respond_to?(:cask?)
        return unless @args.cask?

        # NOTE: We don't raise an error here because we don't want
        #       to print the help page or a stack trace.
        odie "Invalid `--cask` usage: Casks do not work on Linux"
      end
    end
  end
end
