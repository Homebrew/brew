# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"

module Homebrew
  module DevCmd
    class BumpRevision < AbstractCommand
      cmd_args do
        description <<~EOS
          Create a commit to increment the revision of <formula>. If no revision is
          present, "revision 1" will be added.
        EOS
        switch "-n", "--dry-run",
               description: "Print what would be done rather than doing it."
        switch "--remove-bottle-block",
               description: "Remove the bottle block in addition to bumping the revision."
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

        Homebrew.install_bundler_gems!(groups: ["ast"]) unless args.dry_run?

        args.named.to_formulae.each do |formula|
          current_revision = formula.revision
          new_revision = current_revision + 1

          if args.dry_run?
            unless args.quiet?
              old_text = "revision #{current_revision}"
              new_text = "revision #{new_revision}"
              if current_revision.zero?
                ohai "add #{new_text.inspect}"
              else
                ohai "replace #{old_text.inspect} with #{new_text.inspect}"
              end
            end
          else
            require "utils/ast"

            formula_ast = Utils::AST::FormulaAST.new(formula.path.read)
            if current_revision.zero?
              formula_ast.add_stanza(:revision, new_revision)
            else
              formula_ast.replace_stanza(:revision, new_revision)
            end
            formula_ast.remove_stanza(:bottle) if args.remove_bottle_block?
            formula.path.atomic_write(formula_ast.process)
          end

          message = "#{formula.name}: revision bump #{args.message}"
          if args.dry_run?
            ohai "git commit --no-edit --verbose --message=#{message} -- #{formula.path}"
          elsif !args.write_only?
            formula.path.parent.cd do
              safe_system "git", "commit", "--no-edit", "--verbose",
                          "--message=#{message}", "--", formula.path
            end
          end
        end
      end
    end
  end
end
