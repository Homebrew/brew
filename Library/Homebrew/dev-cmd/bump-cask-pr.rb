# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "bump_version_parser"
require "cask"
require "cask/download"
require "utils/tar"

module Homebrew
  module DevCmd
    class BumpCaskPr < AbstractCommand
      cmd_args do
        description <<~EOS
          Create a pull request to update <cask> with a new version.

          A best effort to determine the <SHA-256> will be made if the value is not
          supplied by the user.
        EOS
        switch "-n", "--dry-run",
               description: "Print what would be done rather than doing it."
        switch "--write-only",
               description: "Make the expected file modifications without taking any Git actions."
        switch "--commit",
               depends_on:  "--write-only",
               description: "When passed with `--write-only`, generate a new commit after writing changes " \
                            "to the cask file."
        switch "--no-audit",
               description: "Don't run `brew audit` before opening the PR."
        switch "--no-style",
               description: "Don't run `brew style --fix` before opening the PR."
        switch "--no-browse",
               description: "Print the pull request URL instead of opening in a browser."
        switch "--no-fork",
               description: "Don't try to fork the repository."
        flag   "--version=",
               description: "Specify the new <version> for the cask."
        flag   "--version-arm=",
               description: "Specify the new cask <version> for the ARM architecture."
        flag   "--version-intel=",
               description: "Specify the new cask <version> for the Intel architecture."
        flag   "--message=",
               description: "Prepend <message> to the default pull request message."
        flag   "--url=",
               description: "Specify the <URL> for the new download."
        flag   "--sha256=",
               description: "Specify the <SHA-256> checksum of the new download."
        flag   "--fork-org=",
               description: "Use the specified GitHub organization for forking."

        conflicts "--dry-run", "--write"
        conflicts "--version=", "--version-arm="
        conflicts "--version=", "--version-intel="

        named_args :cask, number: 1, without_api: true
      end

      sig { override.void }
      def run
        # This will be run by `brew audit` or `brew style` later so run it first to
        # not start spamming during normal output.
        gem_groups = []
        gem_groups << "style" if !args.no_audit? || !args.no_style?
        gem_groups << "audit" unless args.no_audit?
        Homebrew.install_bundler_gems!(groups: gem_groups) unless gem_groups.empty?

        # As this command is simplifying user-run commands then let's just use a
        # user path, too.
        ENV["PATH"] = PATH.new(ORIGINAL_PATHS).to_s

        # Use the user's browser, too.
        ENV["BROWSER"] = EnvConfig.browser

        cask = args.named.to_casks.fetch(0)

        odie "This cask is not in a tap!" if cask.tap.blank?
        odie "This cask's tap is not a Git repository!" unless cask.tap.git?

        odie <<~EOS unless cask.tap.allow_bump?(cask.token)
          Whoops, the #{cask.token} cask has its version update
          pull requests automatically opened by BrewTestBot every ~3 hours!
          We'd still love your contributions, though, so try another one
          that is excluded from autobump list (i.e. it has 'no_autobump!'
          method or 'livecheck' block with 'skip'.)
        EOS

        if !args.write_only? && GitHub.too_many_open_prs?(cask.tap)
          odie "You have too many PRs open: close or merge some first!"
        end

        new_version = BumpVersionParser.new(
          general: args.version,
          intel:   args.version_intel,
          arm:     args.version_arm,
        )

        new_hash = unless (new_hash = args.sha256).nil?
          raise UsageError, "`--sha256` must not be empty." if new_hash.blank?

          ["no_check", ":no_check"].include?(new_hash) ? :no_check : new_hash
        end

        new_base_url = unless (new_base_url = args.url).nil?
          raise UsageError, "`--url` must not be empty." if new_base_url.blank?

          begin
            URI(new_base_url)
          rescue URI::InvalidURIError
            raise UsageError, "`--url` is not valid."
          end
        end

        if new_version.blank? && new_base_url.nil? && new_hash.nil?
          raise UsageError, "No `--version`, `--url` or `--sha256` argument specified!"
        end

        check_pull_requests(cask, new_version:) unless args.write_only?

        replacement_pairs ||= []
        branch_name = "bump-#{cask.token}"
        commit_message = nil

        old_contents = File.read(cask.sourcefile_path)

        if new_base_url
          commit_message ||= "#{cask.token}: update URL"

          m = /^ +url "(.+?)"\n/m.match(old_contents)
          odie "Could not find old URL in cask!" if m.nil?

          old_base_url = m.captures.fetch(0)

          replacement_pairs << [
            /#{Regexp.escape(old_base_url)}/,
            new_base_url.to_s,
          ]
        end

        if new_version.present?
          # For simplicity, our naming defers to the arm version if multiple architectures are specified
          branch_version = new_version.arm || new_version.general
          if branch_version.is_a?(Cask::DSL::Version)
            commit_version = shortened_version(branch_version, cask:)
            branch_name = "bump-#{cask.token}-#{branch_version.tr(",:", "-")}"
            commit_message ||= "#{cask.token} #{commit_version}"
          end
          replacement_pairs = replace_version_and_checksum(cask, new_hash, new_version, replacement_pairs)
        end
        # Now that we have all replacement pairs, we will replace them further down

        commit_message ||= "#{cask.token}: update checksum" if new_hash

        # Remove nested arrays where elements are identical
        replacement_pairs = replacement_pairs.reject { |pair| pair[0] == pair[1] }.uniq.compact
        Utils::Inreplace.inreplace_pairs(cask.sourcefile_path,
                                         replacement_pairs,
                                         read_only_run: args.dry_run?,
                                         silent:        args.quiet?)

        run_cask_audit(cask, old_contents)
        run_cask_style(cask, old_contents)

        pr_info = {
          commits:     [{
            commit_message:,
            old_contents:,
            sourcefile_path: cask.sourcefile_path,
          }],
          branch_name:,
          pr_message:  "Created with `brew bump-cask-pr`.",
          tap:         cask.tap,
          pr_title:    commit_message,
        }

        GitHub.create_bump_pr(pr_info, args:) unless args.write_only?
      end

      private

      sig { params(version: Cask::DSL::Version, cask: Cask::Cask).returns(Cask::DSL::Version) }
      def shortened_version(version, cask:)
        if version.before_comma == cask.version.before_comma
          version
        else
          version.before_comma
        end
      end

      sig { params(cask: Cask::Cask).returns(T::Array[[Symbol, Symbol]]) }
      def generate_system_options(cask)
        current_os = Homebrew::SimulateSystem.current_os
        current_os_is_macos = MacOSVersion::SYMBOLS.include?(current_os)
        newest_macos = MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym

        depends_on_archs = cask.depends_on.arch&.filter_map { |arch| arch[:type] }&.uniq

        # NOTE: We substitute the newest macOS (e.g. `:sequoia`) in place of
        # `:macos` values (when used), as a generic `:macos` value won't apply
        # to on_system blocks referencing macOS versions.
        os_values = []
        arch_values = depends_on_archs.presence || []
        if cask.on_system_blocks_exist?
          OnSystem::BASE_OS_OPTIONS.each do |os|
            os_values << if os == :macos
              (current_os_is_macos ? current_os : newest_macos)
            else
              os
            end
          end

          arch_values = OnSystem::ARCH_OPTIONS if arch_values.empty?
        else
          # Architecture is only relevant if on_system blocks are present or
          # the cask uses `depends_on arch`, otherwise we default to ARM for
          # consistency.
          os_values << (current_os_is_macos ? current_os : newest_macos)
          arch_values << :arm if arch_values.empty?
        end

        os_values.product(arch_values)
      end

      sig {
        params(
          cask:              Cask::Cask,
          new_hash:          T.any(NilClass, String, Symbol),
          new_version:       BumpVersionParser,
          replacement_pairs: T::Array[[T.any(Regexp, String), T.any(Pathname, String)]],
        ).returns(T::Array[[T.any(Regexp, String), T.any(Pathname, String)]])
      }
      def replace_version_and_checksum(cask, new_hash, new_version, replacement_pairs)
        generate_system_options(cask).each do |os, arch|
          SimulateSystem.with(os:, arch:) do
            # Handle the cask being invalid for specific os/arch combinations
            old_cask = begin
              Cask::CaskLoader.load(cask.sourcefile_path)
            rescue Cask::CaskInvalidError, Cask::CaskUnreadableError
              raise unless cask.on_system_blocks_exist?
            end
            next if old_cask.nil?

            old_version = old_cask.version
            next unless old_version

            bump_version = new_version.send(arch) || new_version.general

            old_version_regex = old_version.latest? ? ":latest" : %Q(["']#{Regexp.escape(old_version.to_s)}["'])
            replacement_pairs << [/version\s+#{old_version_regex}/m,
                                  "version #{bump_version.latest? ? ":latest" : %Q("#{bump_version}")}"]

            # We are replacing our version here so we can get the new hash
            tmp_contents = Utils::Inreplace.inreplace_pairs(cask.sourcefile_path,
                                                            replacement_pairs.uniq.compact,
                                                            read_only_run: true,
                                                            silent:        true)

            tmp_cask = Cask::CaskLoader::FromContentLoader.new(tmp_contents)
                                                          .load(config: nil)
            old_hash = tmp_cask.sha256
            if tmp_cask.version.latest? || new_hash == :no_check
              opoo "Ignoring specified `--sha256=` argument." if new_hash.is_a?(String)
              replacement_pairs << [/"#{old_hash}"/, ":no_check"] if old_hash != :no_check
            elsif old_hash == :no_check && new_hash != :no_check
              replacement_pairs << [":no_check", "\"#{new_hash}\""] if new_hash.is_a?(String)
            elsif new_hash && !cask.on_system_blocks_exist? && cask.languages.empty?
              replacement_pairs << [old_hash.to_s, new_hash.to_s]
            elsif old_hash != :no_check
              opoo "Multiple checksum replacements required; ignoring specified `--sha256` argument." if new_hash
              languages = if cask.languages.empty?
                [nil]
              else
                cask.languages
              end
              languages.each do |language|
                new_cask        = Cask::CaskLoader.load(tmp_contents)
                new_cask.config = if language.blank?
                  tmp_cask.config
                else
                  tmp_cask.config.merge(Cask::Config.new(explicit: { languages: [language] }))
                end
                download = Cask::Download.new(new_cask, quarantine: true).fetch(verify_download_integrity: false)
                Utils::Tar.validate_file(download)

                if new_cask.sha256.to_s != download.sha256
                  replacement_pairs << [new_cask.sha256.to_s,
                                        download.sha256]
                end
              end
            end
          end
        end
        replacement_pairs
      end

      sig { params(cask: Cask::Cask, new_version: BumpVersionParser).void }
      def check_pull_requests(cask, new_version:)
        tap_remote_repo = cask.tap.full_name || cask.tap.remote_repository

        file = cask.sourcefile_path.relative_path_from(cask.tap.path).to_s
        quiet = args.quiet?
        official_tap = cask.tap.official?
        GitHub.check_for_duplicate_pull_requests(cask.token, tap_remote_repo,
                                                 state: "open", file:, quiet:, official_tap:)

        # if we haven't already found open requests, try for an exact match across all pull requests
        new_version.instance_variables.each do |version_type|
          version_type_version = new_version.instance_variable_get(version_type)
          next if version_type_version.blank?

          version = shortened_version(version_type_version, cask:)
          GitHub.check_for_duplicate_pull_requests(cask.token, tap_remote_repo, version:,
                                                   file:, quiet:, official_tap:)
        end
      end

      sig { params(cask: Cask::Cask, old_contents: String).void }
      def run_cask_audit(cask, old_contents)
        if args.dry_run?
          if args.no_audit?
            ohai "Skipping `brew audit`"
          else
            ohai "brew audit --cask --online #{cask.full_name}"
          end
          return
        end
        failed_audit = false
        if args.no_audit?
          ohai "Skipping `brew audit`"
        else
          system HOMEBREW_BREW_FILE, "audit", "--cask", "--online", cask.full_name
          failed_audit = !$CHILD_STATUS.success?
        end
        return unless failed_audit

        cask.sourcefile_path.atomic_write(old_contents)
        odie "`brew audit` failed!"
      end

      sig { params(cask: Cask::Cask, old_contents: String).void }
      def run_cask_style(cask, old_contents)
        if args.dry_run?
          if args.no_style?
            ohai "Skipping `brew style --fix`"
          else
            ohai "brew style --fix #{cask.sourcefile_path.basename}"
          end
          return
        end
        failed_style = false
        if args.no_style?
          ohai "Skipping `brew style --fix`"
        else
          system HOMEBREW_BREW_FILE, "style", "--fix", cask.sourcefile_path
          failed_style = !$CHILD_STATUS.success?
        end
        return unless failed_style

        cask.sourcefile_path.atomic_write(old_contents)
        odie "`brew style --fix` failed!"
      end
    end
  end
end
