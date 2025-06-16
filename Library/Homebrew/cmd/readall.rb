# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "readall"
require "env_config"

module Homebrew
  module Cmd
    class ReadallCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Import all items from the specified <tap>, or from all installed taps if none is provided.
          This can be useful for debugging issues across all items when making
          significant changes to `formula.rb`, testing the performance of loading
          all items or checking if any current formulae/casks have Ruby issues.
        EOS
        flag   "--os=",
               description: "Read using the given operating system. (Pass `all` to simulate all operating systems.)"
        flag   "--arch=",
               description: "Read using the given CPU architecture. (Pass `all` to simulate all architectures.)"
        switch "--aliases",
               description: "Verify any alias symlinks in each tap."
        switch "--syntax",
               description: "Syntax-check all of Homebrew's Ruby files (if no <tap> is passed)."
        switch "--eval-all",
               description: "Evaluate all available formulae and casks, whether installed or not. " \
                            "Implied if `$HOMEBREW_EVAL_ALL` is set."
        switch "--no-simulate",
               description: "Don't simulate other system configurations when checking formulae and casks."

        named_args :tap
      end

      sig { override.void }
      def run
        Homebrew.with_no_api_env do
          if args.syntax? && args.no_named?
            scan_files = "#{HOMEBREW_LIBRARY_PATH}/**/*.rb"
            ruby_files = Dir.glob(scan_files).grep_v(%r{/(vendor)/})

            Homebrew.failed = true unless Readall.valid_ruby_syntax?(ruby_files)
          end

          options = {
            aliases:     args.aliases?,
            no_simulate: args.no_simulate?,
          }
          options[:os_arch_combinations] = args.os_arch_combinations if args.os || args.arch

          taps = if args.no_named?
            if !args.eval_all? && !Homebrew::EnvConfig.eval_all?
              raise UsageError, "`brew readall` needs a tap or `--eval-all` passed or `$HOMEBREW_EVAL_ALL` set!"
            end

            Tap.installed
          else
            args.named.to_installed_taps
          end

          taps.each do |tap|
            Homebrew.failed = true unless Readall.valid_tap?(tap, **options)
          end
        end
      end
    end
  end
end
