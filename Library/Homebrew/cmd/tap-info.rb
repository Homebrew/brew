# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class TapInfo < AbstractCommand
      cmd_args do
        description <<~EOS
          Show detailed information about one or more <tap>s.
          If no <tap> names are provided, display brief statistics for all installed taps.
        EOS
        switch "--installed",
               description: "Show information on each installed tap."
        flag   "--json",
               description: "Print a JSON representation of <tap>. Currently the default and only accepted " \
                            "value for <version> is `v1`. See the docs for examples of using the JSON " \
                            "output: <https://docs.brew.sh/Querying-Brew>"

        named_args :tap
      end

      sig { override.void }
      def run
        require "tap"

        taps = if args.installed?
          Tap
        else
          args.named.to_taps
        end

        if args.json
          raise UsageError, "invalid JSON version: #{args.json}" unless ["v1", true].include? args.json

          print_tap_json(taps.sort_by(&:to_s))
        else
          print_tap_info(taps.sort_by(&:to_s))
        end
      end

      private

      sig { params(taps: T::Array[Tap]).void }
      def print_tap_info(taps)
        if taps.none?
          tap_count = 0
          formula_count = 0
          command_count = 0
          private_count = 0
          Tap.installed.each do |tap|
            tap_count += 1
            formula_count += tap.formula_files.size
            command_count += tap.command_files.size
            private_count += 1 if tap.private?
          end
          info = Utils.pluralize("tap", tap_count, include_count: true)
          info += ", #{private_count} private"
          info += ", #{Utils.pluralize("formula", formula_count, plural: "e", include_count: true)}"
          info += ", #{Utils.pluralize("command", command_count, include_count: true)}"
          info += ", #{HOMEBREW_TAP_DIRECTORY.dup.abv}" if HOMEBREW_TAP_DIRECTORY.directory?
          puts info
        else
          info = ""
          default_branches = %w[main master].freeze

          taps.each_with_index do |tap, i|
            puts unless i.zero?
            info = "#{tap}: "
            if tap.installed?
              info += "Installed"
              info += if (contents = tap.contents).blank?
                "\nNo commands/casks/formulae"
              else
                "\n#{contents.join(", ")}"
              end
              info += "\nPrivate" if tap.private?
              info += "\n#{tap.path} (#{tap.path.abv})"
              info += "\nFrom: #{tap.remote.presence || "N/A"}"
              info += "\norigin: #{tap.remote}" if tap.remote != tap.default_remote
              info += "\nHEAD: #{tap.git_head || "(none)"}"
              info += "\nlast commit: #{tap.git_last_commit || "never"}"
              info += "\nbranch: #{tap.git_branch || "(none)"}" if default_branches.exclude?(tap.git_branch)
            else
              info += "Not installed"
            end
            puts info
          end
        end
      end

      sig { params(taps: T::Array[Tap]).void }
      def print_tap_json(taps)
        puts JSON.pretty_generate(taps.map(&:to_hash))
      end
    end
  end
end
