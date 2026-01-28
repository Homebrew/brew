# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "keg"
require "cask/caskroom"
require "api"

module Homebrew
  module Cmd
    class Outdated < AbstractCommand
      cmd_args do
        description <<~EOS
          List installed casks and formulae that have an updated version available. By default, version
          information is displayed in interactive shells and suppressed otherwise.
        EOS
        switch "-q", "--quiet",
               description: "List only the names of outdated kegs (takes precedence over `--verbose`)."
        switch "-v", "--verbose",
               description: "Include detailed version information."
        switch "--formula", "--formulae",
               description: "List only outdated formulae."
        switch "--cask", "--casks",
               description: "List only outdated casks."
        flag   "--json",
               description: "Print output in JSON format. There are two versions: `v1` and `v2`. " \
                            "`v1` is deprecated and is currently the default if no version is specified. " \
                            "`v2` prints outdated formulae and casks."
        switch "--fetch-HEAD",
               description: "Fetch the upstream repository to detect if the HEAD installation of the " \
                            "formula is outdated. Otherwise, the repository's HEAD will only be checked for " \
                            "updates when a new stable or development version has been released."
        switch "-g", "--greedy",
               description: "Also include outdated casks with `auto_updates true` or `version :latest`.",
               env:         :upgrade_greedy
        switch "--greedy-latest",
               description: "Also include outdated casks including those with `version :latest`."
        switch "--greedy-auto-updates",
               description: "Also include outdated casks including those with `auto_updates true`."

        conflicts "--quiet", "--verbose", "--json"
        conflicts "--formula", "--cask"

        named_args [:formula, :cask]
      end

      sig { override.void }
      def run
        case json_version(args.json)
        when :v1
          odie "`brew outdated --json=v1` is no longer supported. Use brew outdated --json=v2 instead."
        when :v2, :default
          formulae, casks = if args.formula?
            [outdated_formulae, []]
          elsif args.cask?
            [[], outdated_casks]
          else
            outdated_formulae_casks
          end

          json = {
            formulae: json_info(formulae),
            casks:    json_info(casks),
          }
          # json v2.8.1 is inconsistent it how it renders empty arrays,
          # so we use `[]` for consistency:
          puts JSON.pretty_generate(json).gsub(/\[\n\n\s*\]/, "[]")

          outdated = formulae + casks
        else
          outdated = if args.formula?
            outdated_formulae
          elsif args.cask?
            outdated_casks
          else
            outdated_formulae_casks.flatten
          end

          print_outdated(outdated)
        end

        Homebrew.failed = args.named.present? && outdated.present?
      end

      private

      sig { params(formulae_or_casks: T::Array[T.any(Formula, Cask::Cask)]).void }
      def print_outdated(formulae_or_casks)
        formulae_or_casks.each do |formula_or_cask|
          if formula_or_cask.is_a?(Formula)
            f = formula_or_cask

            if verbose?
              outdated_kegs = f.outdated_kegs(fetch_head: args.fetch_HEAD?)
              latest_formula = f.latest_formula(prefer_stub: true)

              current_version = if f.alias_changed? && !latest_formula.latest_version_installed?
                "#{latest_formula.name} (#{latest_formula.pkg_version})"
              elsif f.head?
                latest_head_version = f.latest_head_pkg_version(fetch_head: args.fetch_HEAD?)
                if outdated_kegs.any? { |k| k.version.to_s == latest_head_version.to_s }
                  # There is a newer HEAD but the version number has not changed.
                  "latest HEAD"
                else
                  latest_head_version.to_s
                end
              else
                latest_formula.pkg_version.to_s
              end

              outdated_versions = outdated_kegs.group_by { |keg| Formulary.from_keg(keg).full_name }
                                               .sort_by { |full_name, _kegs| full_name }
                                               .map do |full_name, kegs|
                "#{full_name} (#{kegs.map(&:version).join(", ")})"
              end.join(", ")

              pinned_version = " [pinned at #{f.pinned_version}]" if f.pinned?

              puts "#{outdated_versions} < #{current_version}#{pinned_version}"
            else
              puts f.full_installed_specified_name
            end
          else
            c = formula_or_cask

            puts c.outdated_info(upgrade_greedy_cask?(args.greedy?, formula_or_cask), verbose?,
                                 false, args.greedy_latest?, args.greedy_auto_updates?)
          end
        end
      end

      sig {
        params(
          formulae_or_casks: T::Array[T.any(Formula, Cask::Cask)],
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      }
      def json_info(formulae_or_casks)
        formulae_or_casks.map do |formula_or_cask|
          if formula_or_cask.is_a?(Formula)
            f = formula_or_cask

            outdated_versions = f.outdated_kegs(fetch_head: args.fetch_HEAD?).map(&:version)
            current_version = if f.head? && outdated_versions.any? { |v| v.to_s == f.pkg_version.to_s }
              "HEAD"
            else
              f.pkg_version.to_s
            end

            { name:               f.full_name,
              installed_versions: outdated_versions.map(&:to_s),
              current_version:,
              pinned:             f.pinned?,
              pinned_version:     f.pinned_version }
          else
            c = formula_or_cask

            c.outdated_info(upgrade_greedy_cask?(args.greedy?, formula_or_cask),
                            verbose?, true, args.greedy_latest?, args.greedy_auto_updates?)
          end
        end
      end

      sig { returns(T::Boolean) }
      def verbose?
        ($stdout.tty? || Context.current.verbose?) && !Context.current.quiet?
      end

      sig { params(version: T.nilable(T.any(TrueClass, String))).returns(T.nilable(Symbol)) }
      def json_version(version)
        version_hash = {
          nil  => nil,
          true => :default,
          "v1" => :v1,
          "v2" => :v2,
        }
        version_hash.fetch(version) { raise UsageError, "invalid JSON version: #{version}" }
      end

      sig { returns(T::Array[Formula]) }
      def outdated_formulae
        T.cast(
          select_outdated(args.named.to_resolved_formulae.presence || Formula.installed).sort,
          T::Array[Formula],
        )
      end

      sig { returns(T::Array[Cask::Cask]) }
      def outdated_casks
        outdated = if args.named.present?
          select_outdated(args.named.to_casks)
        else
          select_outdated(Cask::Caskroom.casks)
        end

        T.cast(outdated, T::Array[Cask::Cask])
      end

      sig { returns([T::Array[T.any(Formula, Cask::Cask)], T::Array[T.any(Formula, Cask::Cask)]]) }
      def outdated_formulae_casks
        formulae, casks = args.named.to_resolved_formulae_to_casks

        if formulae.blank? && casks.blank?
          formulae = Formula.installed
          casks = Cask::Caskroom.casks
        end

        [select_outdated(formulae).sort, select_outdated(casks)]
      end

      sig {
        params(formulae_or_casks: T::Array[T.any(Formula, Cask::Cask)]).returns(T::Array[T.any(Formula, Cask::Cask)])
      }
      def select_outdated(formulae_or_casks)
        formulae_or_casks.select do |formula_or_cask|
          if formula_or_cask.is_a?(Formula)
            formula_or_cask.outdated?(fetch_head: args.fetch_HEAD?)
          else
            formula_or_cask.outdated?(greedy:              upgrade_greedy_cask?(args.greedy?, formula_or_cask),
                                      greedy_latest:       args.greedy_latest?,
                                      greedy_auto_updates: args.greedy_auto_updates?)
          end
        end
      end

      sig { params(greedy: T::Boolean, cask: Cask::Cask).returns(T::Boolean) }
      def upgrade_greedy_cask?(greedy, cask)
        return true if greedy

        @greedy_list ||= T.let(
          begin
            upgrade_greedy_casks = Homebrew::EnvConfig.upgrade_greedy_casks.presence
            upgrade_greedy_casks&.split || []
          end, T.nilable(T::Array[String])
        )

        @greedy_list.include?(cask.token)
      end
    end
  end
end
