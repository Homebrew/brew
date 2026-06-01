# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "bump"
require "bump_version_parser"
require "cask"
require "cask/download"
require "livecheck/livecheck"
require "livecheck/livecheck_version"
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
        conflicts "--version", "--version-arm"
        conflicts "--version", "--version-intel"

        named_args :cask, number: 1, without_api: true
      end

      sig { override.void }
      def run
        # This will be run by `brew audit` or `brew style` later so run it first to
        # not start spamming during normal output.
        gem_groups = ["ast"]
        gem_groups << "style" if !args.no_audit? || !args.no_style?
        gem_groups << "audit" unless args.no_audit?
        Homebrew.install_bundler_gems!(groups: gem_groups)
        require "utils/ast"

        # As this command is simplifying user-run commands then let's just use a
        # user path, too.
        ENV["PATH"] = PATH.new(ORIGINAL_PATHS).to_s

        # Use the user's browser, too.
        ENV["BROWSER"] = EnvConfig.browser

        @cask_retried = T.let(false, T.nilable(T::Boolean))
        cask = begin
          args.named.to_casks.fetch(0)
        rescue Cask::CaskUnavailableError
          raise if @cask_retried

          CoreCaskTap.instance.install(force: true)
          @cask_retried = true
          retry
        end

        tap = cask.tap
        odie "This cask is not in a tap!" if tap.nil?

        odie "This cask's tap is not a Git repository!" unless tap.git?

        odie <<~EOS unless tap.allow_bump?(cask.token)
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

        check_throttle(cask, new_version:)
        check_pull_requests(cask, new_version:) unless args.write_only?

        branch_name = "bump-#{cask.token}"
        commit_message = nil

        sourcefile_path = cask.sourcefile_path
        raise "unexpected nil cask.sourcefile_path" unless sourcefile_path

        old_contents = sourcefile_path.read
        new_contents = old_contents

        if new_base_url
          commit_message ||= "#{cask.token}: update URL"

          cask_ast = Utils::AST::CaskAST.new(new_contents)
          cask_ast.replace_first_stanza_value(:url, new_base_url.to_s)
          new_contents = cask_ast.process
        end

        if new_version.present?
          # For simplicity, our naming defers to the arm version if multiple architectures are specified
          branch_version = new_version.arm || new_version.intel || new_version.general
          if branch_version.is_a?(Cask::DSL::Version)
            commit_version = shortened_version(branch_version, cask:)
            branch_name = "bump-#{cask.token}-#{branch_version.tr(",:", "-")}"
            commit_message ||= "#{cask.token} #{commit_version}"

            # Append an arch-only suffix to the branch name and parenthetical to
            # the commit title if the cask is multi-arch but only one arch is
            # being updated
            if new_version.arm && !new_version.intel
              branch_name += "-arm-only"
              commit_message += " (arm only)"
            elsif new_version.intel && !new_version.arm
              branch_name += "-intel-only"
              commit_message += " (intel only)"
            end
          end
          new_contents = replace_version_and_checksum(cask, new_hash, new_version, new_contents)
        end

        commit_message ||= "#{cask.token}: update checksum" if new_hash

        # We should have already thrown UsageError above if there's nothing to update
        raise "Expected to have a commit message" if commit_message.nil?

        sourcefile_path.atomic_write(new_contents) unless args.dry_run?

        audit_exceptions = []
        audit_exceptions << ["min_os", "rosetta", "signing"] if ENV["HOMEBREW_TEST_BOT_AUTOBUMP"].present?
        run_cask_audit(cask, old_contents, audit_exceptions)
        run_cask_style(cask, old_contents)

        return if args.write_only? && !args.commit?

        url = Homebrew::Bump.create_pr(
          Homebrew::Bump::BumpInfo.new(
            package_tap: cask.tap,
            branch_name:,
            pr_title:    commit_message,
            pr_message:  Homebrew::Bump.pr_message("bump-cask-pr", user_message: args.message),
            commits:     [
              Homebrew::Bump::Commit.new(
                sourcefile_path:,
                old_contents:,
                commit_message:,
              ),
            ],
          ),
          dry_run:  args.dry_run?,
          no_fork:  args.no_fork? || args.write_only?,
          fork_org: args.fork_org,
          commit:   args.commit?,
        )
        return if url.blank?

        if args.no_browse?
          puts url
        else
          exec_browser url
        end
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

      sig { params(cask: Cask::Cask, new_version: BumpVersionParser).returns(T::Array[[Symbol, Symbol]]) }
      def generate_system_options(cask, new_version)
        current_os = Homebrew::SimulateSystem.current_os
        current_os_is_macos = MacOSVersion::SYMBOLS.include?(current_os)
        newest_macos = MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym

        # NOTE: We substitute the newest macOS (e.g. `:sequoia`) in place of
        # `:macos` values (when used), as a generic `:macos` value won't apply
        # to on_system blocks referencing macOS versions.
        os_values = []

        arch_values = []
        if new_version.arm || new_version.intel
          arch_values << :arm if new_version.arm
          arch_values << :intel if new_version.intel
        end

        if cask.on_system_blocks_exist?
          OnSystem::BASE_OS_OPTIONS.each do |os|
            os_values << if os == :macos
              (current_os_is_macos ? current_os : newest_macos)
            else
              os
            end
          end

          # `depends_on arch:` may be scoped to an `on_os` block, so arch
          # filtering is deferred to `replace_version_and_checksum`.
          arch_values = OnSystem::ARCH_OPTIONS.dup if arch_values.empty?
        else
          # Architecture is only relevant if on_system blocks are present or
          # the cask uses `depends_on arch`, otherwise we default to ARM for
          # consistency.
          os_values << (current_os_is_macos ? current_os : newest_macos)
          if arch_values.empty?
            depends_on_archs = cask.depends_on.arch&.filter_map { |arch| arch[:type] }&.uniq
            arch_values = depends_on_archs.presence || [:arm]
          end
        end

        if arch_values.length > 1 && !new_version.general
          # We sort arch values in descending order by version to mitigate the
          # issue where updating multiple arch-specific versions can lead to
          # incorrect version changes in the cask (e.g. ARM is version 1.2.3,
          # Intel is updated to 1.2.3, ARM is updated to 1.2.4 and this
          # incorrectly replaces the 1.2.3 version for both archs). This is
          # something that should be handled by better version replacement logic
          # but this is a workaround for now.
          arch_values = arch_values.sort_by do |type|
            new_version_value = Version.new(new_version.send(type) || "0")
            Livecheck::LivecheckVersion.create(cask, new_version_value)
          end.reverse
        end

        os_values.product(arch_values)
      end

      sig {
        params(
          cask:        Cask::Cask,
          new_hash:    T.nilable(T.any(String, Symbol)),
          new_version: BumpVersionParser,
          contents:    String,
        ).returns(String)
      }
      def replace_version_and_checksum(cask, new_hash, new_version, contents)
        cask_sourcefile_path = cask.sourcefile_path
        raise "unexpected nil cask.sourcefile_path" unless cask_sourcefile_path

        contents = split_root_version_and_checksum(new_version, contents)

        old_cask = Homebrew::SimulateSystem.with(os: default_cask_os, arch: :arm) do
          Cask::CaskLoader.load(cask_sourcefile_path)
        end
        generate_system_options(cask, new_version).each do |os, arch|
          tag = Utils::Bottles::Tag.new(system: os, arch:)
          old_cask.refresh_for_tag(tag) do
            # Skip archs excluded by the cask's `depends_on arch:`.
            reloaded_archs = old_cask.depends_on.arch&.filter_map { |a| a[:type] }&.uniq
            next if reloaded_archs.present? && reloaded_archs.exclude?(arch)

            old_version = old_cask.version
            next unless old_version

            bump_version = new_version.send(arch) || new_version.general
            next unless bump_version

            version_scope = cask_stanza_scope(contents, :version, arch)
            contents = replace_cask_stanza_value(
              contents, :version,
              old_version.latest? ? :latest : old_version.to_s,
              bump_version.latest? ? :latest : bump_version.to_s,
              within: version_scope
            )

            tmp_cask = Cask::CaskLoader::FromContentLoader.new(contents)
                                                          .load(config: nil)
            old_hash = tmp_cask.sha256
            next if new_hash.is_a?(String) && old_hash.to_s == new_hash

            checksum_scope = cask_stanza_scope(contents, :sha256, arch)
            if tmp_cask.version.latest? || new_hash == :no_check
              opoo "Ignoring specified `--sha256=` argument." if new_hash.is_a?(String)
              if old_hash != :no_check
                contents = replace_cask_stanza_value(contents, :sha256, old_hash.to_s, :no_check,
                                                     within: checksum_scope)
              end
            elsif old_hash == :no_check && new_hash != :no_check
              if new_hash.is_a?(String) && (!arch_specific_version_bump?(new_version) || checksum_scope)
                contents = replace_cask_stanza_value(contents, :sha256, :no_check, new_hash, within: checksum_scope)
              end
            elsif new_hash && cask.languages.empty? &&
                  (!cask.on_system_blocks_exist? || checksum_scope || arch_specific_version_bump?(new_version))
              contents = replace_cask_stanza_value(contents, :sha256, old_hash.to_s, new_hash.to_s,
                                                   within: checksum_scope)
            elsif old_hash != :no_check
              opoo "Multiple checksum replacements required; ignoring specified `--sha256` argument." if new_hash
              languages = if cask.languages.empty?
                [nil]
              else
                cask.languages
              end
              languages.each do |language|
                new_cask        = Cask::CaskLoader.load(contents)
                next unless new_cask.url

                new_cask.config = if language.blank?
                  tmp_cask.config
                else
                  tmp_cask.config.merge(Cask::Config.new(explicit: { languages: [language] }))
                end
                download = Cask::Download.new(new_cask, quarantine: true).fetch(verify_download_integrity: false)
                Utils::Tar.validate_file(download)

                if new_cask.sha256.to_s != download.sha256
                  contents = replace_cask_stanza_value(contents, :sha256, new_cask.sha256.to_s, download.sha256,
                                                       within: checksum_scope)
                end
              end
            end
          end
        end
        contents
      end

      sig {
        params(
          new_version: BumpVersionParser,
          contents:    String,
        ).returns(String)
      }
      def split_root_version_and_checksum(new_version, contents)
        return contents unless arch_specific_version_bump?(new_version)

        cask_ast = Utils::AST::CaskAST.new(contents)
        root_version = cask_ast.first_stanza_value(:version, within: :root)
        if root_version &&
           !cask_ast.stanza_anywhere?(:version, within: :on_arm) &&
           !cask_ast.stanza_anywhere?(:version, within: :on_intel)
          cask_ast.replace_root_stanza_with_arch_blocks(:version, root_version)
          contents = cask_ast.process
        end

        cask_ast = Utils::AST::CaskAST.new(contents)
        root_sha256 = cask_ast.first_stanza_value(:sha256, within: :root)
        if root_sha256.is_a?(String) &&
           !cask_ast.stanza_anywhere?(:sha256, within: :on_arm) &&
           !cask_ast.stanza_anywhere?(:sha256, within: :on_intel)
          cask_ast.replace_root_stanza_with_arch_blocks(:sha256, root_sha256)
          contents = cask_ast.process
        end

        contents
      end

      sig { params(new_version: BumpVersionParser).returns(T::Boolean) }
      def arch_specific_version_bump?(new_version)
        new_version.arm.present? || new_version.intel.present?
      end

      sig { returns(Symbol) }
      def default_cask_os
        current_os = Homebrew::SimulateSystem.current_os
        return current_os if MacOSVersion::SYMBOLS.include?(current_os)

        MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym
      end

      sig { params(contents: String, name: Symbol, arch: Symbol).returns(T.nilable(Symbol)) }
      def cask_stanza_scope(contents, name, arch)
        scope = :"on_#{arch}"
        return scope if Utils::AST::CaskAST.new(contents).stanza?(name, within: scope)

        nil
      end

      sig {
        params(
          contents:  String,
          name:      Symbol,
          old_value: T.any(Numeric, String, Symbol),
          new_value: T.any(Numeric, String, Symbol),
          within:    T.nilable(Symbol),
        ).returns(String)
      }
      def replace_cask_stanza_value(contents, name, old_value, new_value, within: nil)
        return contents if old_value == new_value

        cask_ast = Utils::AST::CaskAST.new(contents)
        replacement_count = cask_ast.replace_stanza_value(name, old_value, new_value, within:)
        if replacement_count.zero?
          # Treat an already-applied replacement as a successful no-op so the
          # per-(os, arch) loop in `replace_version_and_checksum` can yield the
          # same general version more than once without raising.
          return contents if cask_ast.replace_stanza_value(name, new_value, new_value, within:).positive?

          raise "Could not find '#{name}' stanza with value #{old_value.inspect}!"
        end

        cask_ast.process
      end

      sig { params(cask: Cask::Cask, new_version: BumpVersionParser).void }
      def check_throttle(cask, new_version:)
        return unless cask.tap

        throttle_rate = cask.livecheck.throttle
        throttle_days = cask.livecheck.throttle_days
        return if throttle_rate.nil? && throttle_days.nil?

        version = new_version.arm || new_version.intel || new_version.general
        return unless version.is_a?(Cask::DSL::Version)

        return if Livecheck.throttle_allows_bump?(cask, version.to_s, throttle_rate:, throttle_days:)

        throttle_items = []
        throttle_items << "#{throttle_rate} releases on multiples of #{throttle_rate}" if throttle_rate
        throttle_items << "#{throttle_days} #{Utils.pluralize("day", throttle_days)}" if throttle_days

        odie "#{cask.token} should only be updated every #{throttle_items.join(" or ")}"
      end

      sig { params(cask: Cask::Cask, new_version: BumpVersionParser).void }
      def check_pull_requests(cask, new_version:)
        tap = cask.tap
        raise "unexpected nil cask.tap" unless tap

        tap_remote_repo = tap.remote_repository
        odie "#{tap.name} tap does not have a remote repository!" unless tap_remote_repo

        sourcefile_path = cask.sourcefile_path
        raise "unexpected nil cask.sourcefile_path" unless sourcefile_path

        file = sourcefile_path.relative_path_from(tap.path).to_s
        quiet = args.quiet?
        official_tap = tap.official?
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

      sig { params(cask: Cask::Cask, old_contents: String, audit_exceptions: T::Array[String]).void }
      def run_cask_audit(cask, old_contents, audit_exceptions = [])
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
          system HOMEBREW_BREW_FILE, "audit", "--cask", "--online", cask.full_name,
                 "--except=#{audit_exceptions.join(",")}"
          failed_audit = !$CHILD_STATUS.success?
        end
        return unless failed_audit

        sourcefile_path = cask.sourcefile_path
        raise "unexpected nil cask.sourcefile_path" unless sourcefile_path

        sourcefile_path.atomic_write(old_contents)
        odie "`brew audit` failed!"
      end

      sig { params(cask: Cask::Cask, old_contents: String).void }
      def run_cask_style(cask, old_contents)
        sourcefile_path = cask.sourcefile_path
        raise "unexpected nil cask.sourcefile_path" unless sourcefile_path

        if args.dry_run?
          if args.no_style?
            ohai "Skipping `brew style --fix`"
          else
            ohai "brew style --fix #{sourcefile_path.basename}"
          end
          return
        end
        failed_style = false
        if args.no_style?
          ohai "Skipping `brew style --fix`"
        else
          system HOMEBREW_BREW_FILE, "style", "--fix", sourcefile_path.to_s
          failed_style = !$CHILD_STATUS.success?
        end
        return unless failed_style

        sourcefile_path.atomic_write(old_contents)
        odie "`brew style --fix` failed!"
      end
    end
  end
end
