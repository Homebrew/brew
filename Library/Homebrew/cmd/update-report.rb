# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "migrator"
require "formulary"
require "cask/cask_loader"
require "cask/caskroom"
require "cask/migrator"
require "descriptions"
require "cleanup"
require "description_cache_store"
require "settings"
require "reinstall"
require "version"

module Homebrew
  module Cmd
    class UpdateReport < AbstractCommand
      cmd_args do
        description <<~EOS
          The Ruby implementation of `brew update`. Never called manually.
        EOS
        switch "--auto-update", "--preinstall",
               description: "Run in 'auto-update' mode (faster, less output)."
        switch "-f", "--force",
               description: "Treat installed and updated formulae as if they are from " \
                            "the same taps and migrate them anyway."

        hide_from_man_page!
      end

      sig { override.void }
      def run
        return output_update_report if $stdout.tty?

        redirect_stdout($stderr) do
          output_update_report
        end
      end

      private

      sig { void }
      def auto_update_header
        @auto_update_header ||= T.let(begin
          ohai "Auto-updated Homebrew!" if args.auto_update?
          true
        end, T.nilable(T::Boolean))
      end

      sig { void }
      def output_update_report
        if ENV["HOMEBREW_ADDITIONAL_GOOGLE_ANALYTICS_ID"].present?
          opoo "HOMEBREW_ADDITIONAL_GOOGLE_ANALYTICS_ID is now a no-op so can be unset."
          puts "All Homebrew Google Analytics code and data was destroyed."
        end

        if ENV["HOMEBREW_NO_GOOGLE_ANALYTICS"].present?
          opoo "HOMEBREW_NO_GOOGLE_ANALYTICS is now a no-op so can be unset."
          puts "All Homebrew Google Analytics code and data was destroyed."
        end

        unless args.quiet?
          analytics_message
          donation_message
          install_from_api_message
        end

        if (redirected_remotes_file = ENV.fetch("HOMEBREW_REDIRECTED_REMOTES_FILE", nil)).present?
          redirected_remotes_path = Pathname(redirected_remotes_file)
          if redirected_remotes_path.file?
            begin
              denied_redirects = []
              redirected_remotes_path.each_line do |line|
                tap_path, redirected_remote = line.chomp.split("\t", 2)
                next if tap_path.blank? || redirected_remote.blank?
                next unless (tap = Tap.from_path(tap_path))

                old_repository_var_suffix = tap.repository_var_suffix
                begin
                  tap.apply_redirected_remote!(redirected_remote, quiet: args.quiet?)
                rescue TapRedirectNotAllowedError => e
                  # update.sh may already have merged redirected content, so roll back every denied tap.
                  before_revision = ENV.fetch("HOMEBREW_UPDATE_BEFORE#{old_repository_var_suffix}", nil)
                  if before_revision.present? && tap.installed?
                    git_args = ["-C", tap.path.to_s]
                    safe_system "git", *git_args, "reset", "--hard", "-q", before_revision
                    branch = Utils.popen_read("git", *git_args, "symbolic-ref", "--short", "-q", "HEAD").chomp
                    branch = branch.presence || tap.git_repository.origin_branch_name
                    if branch.present?
                      safe_system "git", *git_args, "update-ref", "refs/remotes/origin/#{branch}", before_revision
                    end
                  end
                  denied_redirects << e.message
                  next
                end
                new_repository_var_suffix = tap.repository_var_suffix
                next if old_repository_var_suffix == new_repository_var_suffix

                ["HOMEBREW_UPDATE_BEFORE", "HOMEBREW_UPDATE_AFTER"].each do |prefix|
                  old_var = "#{prefix}#{old_repository_var_suffix}"
                  old_value = ENV.fetch(old_var, nil)
                  next if old_value.blank?

                  ENV["#{prefix}#{new_repository_var_suffix}"] ||= old_value
                end
              end
              odie denied_redirects.join("\n\n") if denied_redirects.any?
            ensure
              redirected_remotes_path.unlink if redirected_remotes_path.exist?
            end
          end
        end
        tap_or_untap_core_taps_if_necessary

        updated = false
        new_tag = nil

        initial_revision = ENV["HOMEBREW_UPDATE_BEFORE"].to_s
        current_revision = ENV["HOMEBREW_UPDATE_AFTER"].to_s
        odie "update-report should not be called directly!" if initial_revision.empty? || current_revision.empty?

        if initial_revision != current_revision
          auto_update_header

          updated = true

          old_tag = Settings.read "latesttag"

          new_tag = Utils.popen_read(
            "git", "-C", HOMEBREW_REPOSITORY, "tag", "--list", "--sort=-version:refname", "*.*"
          ).lines.fetch(0).chomp

          Settings.write "latesttag", new_tag if new_tag != old_tag

          if new_tag == old_tag
            ohai "Updated Homebrew from #{shorten_revision(initial_revision)} " \
                 "to #{shorten_revision(current_revision)}."
          elsif old_tag.blank?
            ohai "Updated Homebrew from #{shorten_revision(initial_revision)} " \
                 "to #{new_tag} (#{shorten_revision(current_revision)})."
          else
            ohai "Updated Homebrew from #{old_tag} (#{shorten_revision(initial_revision)}) " \
                 "to #{new_tag} (#{shorten_revision(current_revision)})."
          end
        end

        # Check if we can parse the JSON and do any Ruby-side follow-up.
        Homebrew::API.write_names_and_aliases unless Homebrew::EnvConfig.no_install_from_api?

        Homebrew.failed = true if ENV["HOMEBREW_UPDATE_FAILED"]
        migrate_caskroom_caskfiles_to_json
        return if Homebrew::EnvConfig.disable_load_formula?

        migrate_gcc_dependents_if_needed

        hub = ReporterHub.new

        updated_taps = []
        Tap.installed.each do |tap|
          next if !tap.git? || tap.git_repository.origin_url.nil?
          next if (tap.core_tap? || tap.core_cask_tap?) && !Homebrew::EnvConfig.no_install_from_api?

          begin
            reporter = Reporter.new(tap)
          rescue Reporter::ReporterRevisionUnsetError => e
            if Homebrew::EnvConfig.developer?
              require "utils/backtrace"
              onoe "#{e.message}\n#{Utils::Backtrace.clean(e)&.join("\n")}"
            end
            next
          end
          if reporter.updated?
            updated_taps << tap.name
            hub.add(reporter, auto_update: args.auto_update?)
          end
        end

        # If we're installing from the API: we cannot use Git to check for #
        # differences in packages so instead use {formula,cask}_names.txt to do so.
        # The first time this runs: we won't yet have a base state
        # ({formula,cask}_names.before.txt) to compare against so we don't output a
        # anything and just copy the files for next time.
        unless Homebrew::EnvConfig.no_install_from_api?
          api_cache = Homebrew::API::HOMEBREW_CACHE_API
          core_tap = CoreTap.instance
          cask_tap = CoreCaskTap.instance
          [
            [:formula, core_tap, core_tap.formula_dir],
            [:cask,    cask_tap, cask_tap.cask_dir],
          ].each do |type, tap, dir|
            names_txt = api_cache/"#{type}_names.txt"
            next unless names_txt.exist?

            names_before_txt = api_cache/"#{type}_names.before.txt"
            if names_before_txt.exist?
              reporter = Reporter.new(
                tap,
                api_names_txt:        names_txt,
                api_names_before_txt: names_before_txt,
                api_dir_prefix:       dir,
              )
              if reporter.updated?
                updated_taps << tap.name
                hub.add(reporter, auto_update: args.auto_update?)
              end
            else
              FileUtils.cp names_txt, names_before_txt
            end
          end
        end

        unless updated_taps.empty?
          auto_update_header
          puts "Updated #{Utils.pluralize("tap", updated_taps.count,
                                          include_count: true)} (#{updated_taps.to_sentence})."
          updated = true
        end

        if updated
          if hub.empty?
            puts no_changes_message unless args.quiet?
          else
            if ENV.fetch("HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED", false)
              opoo "HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED is now the default behaviour, " \
                   "so you can unset it from your environment."
            end

            hub.dump(auto_update: args.auto_update?) unless args.quiet?
            hub.reporters.each(&:migrate_tap_migration)
            hub.reporters.each(&:migrate_cask_rename)
            hub.reporters.each { |r| r.migrate_formula_rename(force: args.force?, verbose: args.verbose?) }

            CacheStoreDatabase.use(:descriptions) do |db|
              DescriptionCacheStore.new(T.cast(db, CacheStoreDatabase[String, T.anything]))
                                   .update_from_report!(hub)
            end
            CacheStoreDatabase.use(:cask_descriptions) do |db|
              CaskDescriptionCacheStore.new(T.cast(db, CacheStoreDatabase[String, T.anything]))
                                       .update_from_report!(hub)
            end
          end
          puts if args.auto_update?
        elsif !args.auto_update? && !ENV["HOMEBREW_UPDATE_FAILED"]
          puts "Already up-to-date." unless args.quiet?
        end

        Homebrew::Reinstall.reinstall_pkgconf_if_needed!

        Commands.rebuild_commands_completion_list
        link_completions_manpages_and_docs
        Tap.installed.each(&:link_completions_and_manpages)

        # Only prewarm when the update changed `Library/Homebrew/vendor`:
        # portable Ruby bumps rotate the whole Bootsnap cache key and
        # vendored gem bumps rewrite gem trees this run never loads, while
        # for code-only updates this run has already recompiled most of
        # what the next command needs.
        if !args.auto_update? && initial_revision != current_revision &&
           !quiet_system("git", "-C", HOMEBREW_REPOSITORY.to_s, "diff", "--quiet",
                         initial_revision, current_revision, "--", "Library/Homebrew/vendor")
          Homebrew::Bootsnap.prewarm!
        end

        failed_fetch_dirs = ENV["HOMEBREW_MISSING_REMOTE_REF_DIRS"]&.split("\n")
        if failed_fetch_dirs.present?
          failed_fetch_taps = failed_fetch_dirs.map { |dir| Tap.from_path(dir) }

          ofail <<~EOS
            Some taps failed to update!
            The following taps can not read their remote branches:
              #{failed_fetch_taps.join("\n  ")}
            This is happening because the remote branch was renamed or deleted.
            Reset taps to point to the correct remote branches by running `brew tap --repair`
          EOS
        end

        return if new_tag.blank? || new_tag == old_tag || args.quiet?

        puts

        new_version = ::Version.new(new_tag)
        if new_version.major_minor > ::Version.new(old_tag || "0").major_minor
          puts <<~EOS
            The #{new_version.major_minor}.0 release notes are available on the Homebrew Blog:
              #{Formatter.url("https://brew.sh/blog/#{new_version.major_minor}.0")}
          EOS
        end

        return if new_version.patch.to_i.zero?

        puts <<~EOS
          The #{new_tag} changelog can be found at:
            #{Formatter.url("https://github.com/Homebrew/brew/releases/tag/#{new_tag}")}
        EOS
      end

      sig { returns(String) }
      def no_changes_message
        "No changes to formulae or casks."
      end

      sig { params(revision: String).returns(String) }
      def shorten_revision(revision)
        Utils.popen_read("git", "-C", HOMEBREW_REPOSITORY, "rev-parse", "--short", revision).chomp
      end

      sig { void }
      def tap_or_untap_core_taps_if_necessary
        return if ENV["HOMEBREW_UPDATE_TEST"]

        if Homebrew::EnvConfig.no_install_from_api?
          return if Homebrew::EnvConfig.automatically_set_no_install_from_api?

          core_tap = CoreTap.instance
          return if core_tap.installed?

          core_tap.ensure_installed!
          revision = CoreTap.instance.git_head
          ENV["HOMEBREW_UPDATE_BEFORE_HOMEBREW_HOMEBREW_CORE"] = revision
          ENV["HOMEBREW_UPDATE_AFTER_HOMEBREW_HOMEBREW_CORE"] = revision
        else
          return if Homebrew::EnvConfig.developer? || ENV["HOMEBREW_DEV_CMD_RUN"]
          return if ENV["HOMEBREW_GITHUB_HOSTED_RUNNER"] || ENV["GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED"]
          return if (HOMEBREW_PREFIX/".homebrewdocker").exist?

          tap_output_header_printed = T.let(false, T::Boolean)
          default_branches = %w[main master].freeze
          [CoreTap.instance, CoreCaskTap.instance].each do |tap|
            next unless tap.installed?

            if default_branches.include?(tap.git_branch) &&
               (Date.parse(T.must(tap.git_repository.last_commit_date)) <= Date.today.prev_month)
              ohai "#{tap.name} is old and unneeded, untapping to save space..."
              tap.uninstall
            else
              unless tap_output_header_printed
                puts "Installing from the API is now the default behaviour!"
                puts "You can save space and time by running:"
                tap_output_header_printed = true
              end
              puts "  brew untap #{tap.name}"
            end
          end
        end
      end

      sig { params(repository: Pathname).void }
      def link_completions_manpages_and_docs(repository = HOMEBREW_REPOSITORY)
        command = "brew update"
        Utils::Link.link_completions(repository, command)
        Utils::Link.link_manpages(repository, command)
        Utils::Link.link_docs(repository, command)
      rescue => e
        ofail <<~EOS
          Failed to link all completions, docs and manpages:
            #{e}
        EOS
      end

      sig { void }
      def migrate_gcc_dependents_if_needed
        # do nothing
      end

      sig { void }
      def migrate_caskroom_caskfiles_to_json
        return unless Cask::Caskroom.path.directory?

        Cask::Caskroom.path.glob("*/.metadata/*/*/Casks/*.{internal.json,rb}").each do |caskfile|
          cask = Cask::CaskLoader.load(caskfile, warn: false)
          next if cask.uninstall_flight_blocks?

          (caskfile.dirname/"#{cask.token}.json").atomic_write(JSON.pretty_generate(cask.to_installed_json_hash))
          caskfile.unlink
        rescue => e
          opoo "Failed to migrate #{caskfile} to JSON metadata: #{e}"
        end
      end

      sig { void }
      def analytics_message
        return if Utils::Analytics.messages_displayed?
        return if Utils::Analytics.no_message_output?

        if Utils::Analytics.disabled? && !Utils::Analytics.influx_message_displayed?
          ohai "Homebrew's analytics have entirely moved to our InfluxDB instance in the EU."
          puts "We gather less data than before and have destroyed all Google Analytics data:"
          puts "  #{Formatter.url("https://docs.brew.sh/Analytics")}#{Tty.reset}"
          puts "Please reconsider re-enabling analytics to help our volunteer maintainers with:"
          puts "  brew analytics on"
        elsif !Utils::Analytics.disabled?
          ENV["HOMEBREW_NO_ANALYTICS_THIS_RUN"] = "1"
          # Use the shell's audible bell.
          print "\a"

          # Use an extra newline and bold to avoid this being missed.
          ohai "Homebrew collects anonymous analytics."
          puts <<~EOS
            #{Tty.bold}Read the analytics documentation (and how to opt-out) here:
              #{Formatter.url("https://docs.brew.sh/Analytics")}#{Tty.reset}
            No analytics have been recorded yet (nor will be during this `brew` run).

          EOS
        end

        # Consider the messages possibly missed if not a TTY.
        Utils::Analytics.messages_displayed! if $stdout.tty?
      end

      sig { void }
      def donation_message
        return if Settings.read("donationmessage") == "true"

        ohai "Homebrew is run entirely by unpaid volunteers. Please consider donating:"
        puts "  #{Formatter.url("https://github.com/Homebrew/brew#-donations")}\n\n"

        # Consider the message possibly missed if not a TTY.
        Settings.write "donationmessage", true if $stdout.tty?
      end

      sig { void }
      def install_from_api_message
        return if Settings.read("installfromapimessage") == "true"

        no_install_from_api_set = Homebrew::EnvConfig.no_install_from_api? &&
                                  !Homebrew::EnvConfig.automatically_set_no_install_from_api?
        return unless no_install_from_api_set

        ohai "You have `$HOMEBREW_NO_INSTALL_FROM_API` set"
        puts "Homebrew >=4.1.0 is dramatically faster and less error-prone when installing"
        puts "from the JSON API. Please consider unsetting `$HOMEBREW_NO_INSTALL_FROM_API`."
        puts "This message will only be printed once."
        puts "\n\n"

        # Consider the message possibly missed if not a TTY.
        Settings.write "installfromapimessage", true if $stdout.tty?
      end
    end
  end
end

require "extend/os/cmd/update-report"
require "cmd/update_report/reporter"
require "cmd/update_report/reporter_hub"
