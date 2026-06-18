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
          info += ", #{Utils.pluralize("formula", formula_count, include_count: true)}"
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
              if Homebrew::EnvConfig.require_tap_trust?
                require "trust"
                info += "\n#{Homebrew::Trust.trusted_tap?(tap) ? "Trusted" : "Untrusted"}"
              end
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
              puts info
              print_tap_listings(tap)
            else
              info += "Not installed"
              Homebrew.failed = true
              puts info
            end
          end
        end
      end

      LISTING_LIMIT = 30
      private_constant :LISTING_LIMIT

      sig { params(tap: Tap).void }
      def print_tap_listings(tap)
        commands = tap.command_files
                      .map { |path| path.basename(path.extname).to_s.delete_prefix("brew-") }
                      .sort
        installed_formula_names = Formula.installed_formula_names.to_set
        installed_cask_tokens = Cask::Caskroom.tokens.to_set
        formula_names = tap.formula_names.map { |name| Utils.name_from_full_name(name) }.sort
        cask_tokens = tap.cask_tokens.map { |token| Utils.name_from_full_name(token) }.sort
        installed_formulae = formula_names.select { |name| installed_formula_names.include?(name) }
        installed_casks = cask_tokens.select { |token| installed_cask_tokens.include?(token) }

        if commands.any?
          ohai "Commands"
          puts commands.join(", ")
        end

        min_width = (formula_names + cask_tokens).map { |n| Tty.strip_ansi(pretty_uninstalled(n)).length }.max || 0
        print_section(tap, "Formulae", formula_names, installed_formulae, min_width:) do |name|
          decorate_formula(tap, name, installed: installed_formula_names.include?(name))
        end
        print_section(tap, "Casks", cask_tokens, installed_casks, min_width:) do |token|
          decorate_cask(tap, token, installed: installed_cask_tokens.include?(token))
        end
      end

      sig {
        params(
          tap:       Tap,
          label:     String,
          all:       T::Array[String],
          installed: T::Array[String],
          min_width: Integer,
          block:     T.proc.params(name: String).returns(String),
        ).void
      }
      def print_section(tap, label, all, installed, min_width:, &block)
        return if all.none?

        if all.size <= LISTING_LIMIT
          ohai label, Formatter.columns(all.map(&block), min_width:)
        elsif installed.any?
          ohai label
          opoo "Tap has more than #{LISTING_LIMIT} #{label.downcase}; showing only installed entries."
          puts Formatter.columns(installed.map(&block), min_width:)
        else
          ohai label
          opoo "Tap has more than #{LISTING_LIMIT} #{label.downcase} and none are installed."
          puts "See: #{tap.remote}" if tap.remote.present?
        end
      end

      sig { params(tap: Tap, name: String, installed: T::Boolean).returns(String) }
      def decorate_formula(tap, name, installed:)
        formula = Formulary.factory("#{tap.name}/#{name}")
        pretty_install_status(
          name,
          installed:,
          outdated:         installed && formula.outdated?,
          deprecated:       formula.deprecated?,
          disabled:         formula.disabled?,
          mark_uninstalled: false,
        )
      rescue
        pretty_install_status(name, installed:, mark_uninstalled: false)
      end

      sig { params(tap: Tap, token: String, installed: T::Boolean).returns(String) }
      def decorate_cask(tap, token, installed:)
        cask = Cask::CaskLoader.load("#{tap.name}/#{token}")
        pretty_install_status(
          token,
          installed:,
          outdated:         installed && cask.outdated?,
          deprecated:       cask.deprecated?,
          disabled:         cask.disabled?,
          mark_uninstalled: false,
        )
      rescue
        pretty_install_status(token, installed:, mark_uninstalled: false)
      end

      sig { params(taps: T::Array[Tap]).void }
      def print_tap_json(taps)
        puts JSON.pretty_generate(taps.map(&:to_hash))
      end
    end
  end
end
