# typed: strict
# frozen_string_literal: true

require "system_command"

require "abstract_command"
require "formula"

module Homebrew
  module DevCmd
    class BumpCompatibilityVersion < AbstractCommand
      cmd_args do
        description <<~EOS
          Create a commit to increment the compatibility_version of <formula>. If no
          compatibility_version is present, "compatibility_version 1" will be added.
        EOS
        switch "-n", "--dry-run",
               description: "Print what would be done rather than doing it."
        switch "--write-only",
               description: "Make the expected file modifications without taking any Git actions."
        flag   "--message=",
               description: "Append <message> to the default commit message."

        conflicts "--dry-run", "--write-only"

        named_args :formula, min: 1, without_api: true
      end

      sig { override.void }
      def run
        # As this command is simplifying user-run commands then let's just use a
        # user path, too.
        ENV["PATH"] = PATH.new(ORIGINAL_PATHS).to_s

        Utils::GemSetup.install_bundler_gems!(groups: ["ast"]) unless args.dry_run?

        args.named.to_formulae.each do |formula|
          current_compatibility_version = formula.compatibility_version || 0
          new_compatibility_version = current_compatibility_version + 1

          if args.dry_run?
            unless args.quiet?
              old_text = "compatibility_version #{current_compatibility_version}"
              new_text = "compatibility_version #{new_compatibility_version}"
              if formula.compatibility_version.nil?
                ohai "add #{new_text.inspect}"
              else
                ohai "replace #{old_text.inspect} with #{new_text.inspect}"
              end
            end
          else
            require "utils/ast"

            formula_ast = Utils::AST::FormulaAST.new(formula.path.read)
            if formula.compatibility_version.nil?
              formula_ast.add_stanza(:compatibility_version, new_compatibility_version)
            else
              formula_ast.replace_stanza(:compatibility_version, new_compatibility_version)
            end
            formula.path.atomic_write(formula_ast.process)
          end

          message = "#{formula.name}: compatibility_version bump #{args.message}"
          if args.dry_run?
            ohai "git commit --no-edit --verbose --message=#{message} -- #{formula.path}"
          elsif !args.write_only?
            formula.path.parent.cd do
              SystemCommand.safe_system "git", "commit", "--no-edit", "--verbose",
                                        "--message=#{message}", "--", formula.path
            end
          end
        end
      end
    end
  end
end
