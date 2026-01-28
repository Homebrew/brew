# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "unlink"

module Homebrew
  module Cmd
    class UnlinkCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Remove symlinks for <formula> from Homebrew's prefix. This can be useful
          for temporarily disabling a formula:
          `brew unlink` <formula> `&&` <commands> `&& brew link` <formula>
        EOS
        switch "-n", "--dry-run",
               description: "List files which would be unlinked without actually unlinking or " \
                            "deleting any files."

        named_args :installed_formula, min: 1
      end

      sig { override.void }
      def run
        options = { dry_run: args.dry_run?, verbose: args.verbose? }

        args.named.to_default_kegs.each do |keg|
          if args.dry_run?
            puts "Would remove:"
            keg.unlink(**options)
            next
          end

          Unlink.unlink(keg, dry_run: args.dry_run?, verbose: args.verbose?)
        end
      end
    end
  end
end
