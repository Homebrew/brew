# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula_installer"

module Homebrew
  module Cmd
    class Postinstall < AbstractCommand
      cmd_args do
        description <<~EOS
          Rerun the post-install steps for <formula>.
        EOS

        named_args :installed_formula, min: 1
      end

      sig { override.void }
      def run
        args.named.to_resolved_formulae.each do |f|
          ohai "Postinstalling #{f}"
          f.install_etc_var
          post_install_steps_defined = f.post_install_steps_defined?
          post_install_defined = f.post_install_defined?

          f.run_post_install_steps if post_install_steps_defined
          if post_install_defined
            fi = FormulaInstaller.new(f, **{ debug: args.debug?, quiet: args.quiet?, verbose: args.verbose? }.compact)
            fi.post_install
          elsif !post_install_steps_defined
            opoo "#{f}: no `post_install` method was defined in the formula!"
          end
        end
      end
    end
  end
end
