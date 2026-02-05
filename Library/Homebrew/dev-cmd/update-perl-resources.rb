# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "utils/cpan"

module Homebrew
  module DevCmd
    class UpdatePerlResources < AbstractCommand
      cmd_args do
        description <<~EOS
          Update versions for CPAN resource blocks in <formula>.
        EOS
        switch "-p", "--print-only",
               description: "Print the updated resource blocks instead of changing <formula>."
        switch "-s", "--silent",
               description: "Suppress any output."
        switch "--ignore-errors",
               description: "Continue processing even if some resources can't be resolved."

        named_args :formula, min: 1, without_api: true
      end

      sig { override.void }
      def run
        args.named.to_formulae.each do |formula|
          CPAN.update_perl_resources! formula,
                                      print_only:    args.print_only?,
                                      silent:        args.silent?,
                                      verbose:       args.verbose?,
                                      ignore_errors: args.ignore_errors?
        end
      end
    end
  end
end
