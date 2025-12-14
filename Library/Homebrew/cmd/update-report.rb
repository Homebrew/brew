# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "migrator"
require "formulary"
require "cask/cask_loader"
require "cask/migrator"
require "descriptions"
require "cleanup"
require "description_cache_store"
require "settings"
require "reinstall"

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
          ).lines.first.chomp

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
              DescriptionCacheStore.new(db)
                                   .update_from_report!(hub)
            end
            CacheStoreDatabase.use(:cask_descriptions) do |db|
              CaskDescriptionCacheStore.new(db)
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

        new_major_version, new_minor_version, new_patch_version = new_tag.split(".").map(&:to_i)
        old_major_version, old_minor_version = T.must(old_tag.split(".")[0, 2]).map(&:to_i) if old_tag.present?
        if old_tag.blank? || new_major_version > old_major_version || new_minor_version > old_minor_version
          puts <<~EOS
            The #{new_major_version}.#{new_minor_version}.0 release notes are available on the Homebrew Blog:
              #{Formatter.url("https://brew.sh/blog/#{new_major_version}.#{new_minor_version}.0")}
          EOS
        end

        return if new_patch_version.zero?

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
        puts "  #{Formatter.url("https://github.com/Homebrew/brew#donations")}\n\n"

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

class Reporter
  include Utils::Output::Mixin

  Report = T.type_alias do
    {
      A:  T::Array[String],
      AC: T::Array[String],
      D:  T::Array[String],
      DC: T::Array[String],
      M:  T::Array[String],
      MC: T::Array[String],
      R:  T::Array[[String, String]],
      RC: T::Array[[String, String]],
      T:  T::Array[String],
    }
  end

  class ReporterRevisionUnsetError < RuntimeError
    sig { params(var_name: String).void }
    def initialize(var_name)
      super "#{var_name} is unset!"
    end
  end

  sig {
    params(tap: Tap, api_names_txt: T.nilable(Pathname), api_names_before_txt: T.nilable(Pathname),
           api_dir_prefix: T.nilable(Pathname)).void
  }
  def initialize(tap, api_names_txt: nil, api_names_before_txt: nil, api_dir_prefix: nil)
    @tap = tap

    # This is slightly involved/weird but all the #report logic is shared so it's worth it.
    if installed_from_api?(api_names_txt, api_names_before_txt, api_dir_prefix)
      @api_names_txt = T.let(api_names_txt, T.nilable(Pathname))
      @api_names_before_txt = T.let(api_names_before_txt, T.nilable(Pathname))
      @api_dir_prefix = T.let(api_dir_prefix, T.nilable(Pathname))
    else
      initial_revision_var = "HOMEBREW_UPDATE_BEFORE#{tap.repository_var_suffix}"
      @initial_revision = T.let(ENV[initial_revision_var].to_s, String)
      raise ReporterRevisionUnsetError, initial_revision_var if @initial_revision.empty?

      current_revision_var = "HOMEBREW_UPDATE_AFTER#{tap.repository_var_suffix}"
      @current_revision = T.let(ENV[current_revision_var].to_s, String)
      raise ReporterRevisionUnsetError, current_revision_var if @current_revision.empty?
    end

    @report = T.let(nil, T.nilable(Report))
  end

  sig { params(auto_update: T::Boolean).returns(Report) }
  def report(auto_update: false)
    return @report if @report

    @report = {
      A: [], AC: [], D: [], DC: [], M: [], MC: [], R: T.let([], T::Array[[String, String]]),
      RC: T.let([], T::Array[[String, String]]), T: []
    }
    return @report unless updated?

    diff.each_line do |line|
      status, *paths = line.split
      src = Pathname.new paths.first
      dst = Pathname.new paths.last

      next if dst.extname != ".rb"

      if paths.any? { |p| tap.cask_file?(p) }
        case status
        when "A"
          # Have a dedicated report array for new casks.
          @report[:AC] << tap.formula_file_to_name(src)
        when "D"
          # Have a dedicated report array for deleted casks.
          @report[:DC] << tap.formula_file_to_name(src)
        when "M"
          # Report updated casks
          @report[:MC] << tap.formula_file_to_name(src)
        when /^R\d{0,3}/
          src_full_name = tap.formula_file_to_name(src)
          dst_full_name = tap.formula_file_to_name(dst)
          # Don't report formulae that are moved within a tap but not renamed
          next if src_full_name == dst_full_name

          @report[:DC] << src_full_name
          @report[:AC] << dst_full_name
        end
      end

      next unless paths.any? do |p|
        tap.formula_file?(p) ||
        # Need to check for case where Formula directory was deleted
        (status == "D" && File.fnmatch?("{Homebrew,}Formula/**/*.rb", p, File::FNM_EXTGLOB | File::FNM_PATHNAME))
      end

      case status
      when "A", "D"
        full_name = tap.formula_file_to_name(src)
        name = full_name.split("/").fetch(-1)
        new_tap = tap.tap_migrations[name]
        if new_tap.blank?
          @report[T.must(status).to_sym] << full_name
        elsif status == "D"
          # Retain deleted formulae for tap migrations separately to avoid reporting as deleted
          @report[:T] << full_name
        end
      when "M"
        name = tap.formula_file_to_name(src)

        @report[:M] << name
      when /^R\d{0,3}/
        src_full_name = tap.formula_file_to_name(src)
        dst_full_name = tap.formula_file_to_name(dst)
        # Don't report formulae that are moved within a tap but not renamed
        next if src_full_name == dst_full_name

        @report[:D] << src_full_name
        @report[:A] << dst_full_name
      end
    end

    renamed_casks = Set.new
    @report[:DC].each do |old_full_name|
      old_name = old_full_name.split("/").last
      new_name = tap.cask_renames[old_name]
      next unless new_name

      new_full_name = if tap.core_cask_tap?
        new_name
      else
        "#{tap}/#{new_name}"
      end

      renamed_casks << [old_full_name, new_full_name] if @report[:AC].include?(new_full_name)
    end

    @report[:AC].each do |new_full_name|
      new_name = new_full_name.split("/").last
      old_name = tap.cask_renames.key(new_name)
      next unless old_name

      old_full_name = if tap.core_cask_tap?
        old_name
      else
        "#{tap}/#{old_name}"
      end

      renamed_casks << [old_full_name, new_full_name]
    end

    if renamed_casks.any?
      @report[:AC] -= renamed_casks.map(&:last)
      @report[:DC] -= renamed_casks.map(&:first)
      @report[:RC] = renamed_casks.to_a
    end

    renamed_formulae = Set.new
    @report[:D].each do |old_full_name|
      old_name = old_full_name.split("/").last
      new_name = tap.formula_renames[old_name]
      next unless new_name

      new_full_name = if tap.core_tap?
        new_name
      else
        "#{tap}/#{new_name}"
      end

      renamed_formulae << [old_full_name, new_full_name] if @report[:A].include? new_full_name
    end

    @report[:A].each do |new_full_name|
      new_name = new_full_name.split("/").last
      old_name = tap.formula_renames.key(new_name)
      next unless old_name

      old_full_name = if tap.core_tap?
        old_name
      else
        "#{tap}/#{old_name}"
      end

      renamed_formulae << [old_full_name, new_full_name]
    end

    if renamed_formulae.any?
      @report[:A] -= renamed_formulae.map(&:last)
      @report[:D] -= renamed_formulae.map(&:first)
      @report[:R] = renamed_formulae.to_a
    end

    # If any formulae/casks are marked as added and deleted, remove them from
    # the report as we've not detected things correctly.
    if (added_and_deleted_formulae = (@report[:A] & @report[:D]).presence)
      @report[:A] -= added_and_deleted_formulae
      @report[:D] -= added_and_deleted_formulae
    end
    if (added_and_deleted_casks = (@report[:AC] & @report[:DC]).presence)
      @report[:AC] -= added_and_deleted_casks
      @report[:DC] -= added_and_deleted_casks
    end

    @report
  end

  sig { returns(T::Boolean) }
  def updated?
    if installed_from_api?
      diff.present?
    else
      initial_revision != current_revision
    end
  end

  sig { void }
  def migrate_tap_migration
    [report[:D], report[:DC], report[:T]].flatten.each do |full_name|
      name = full_name.split("/").fetch(-1)
      new_tap_name = tap.tap_migrations[name]
      next if new_tap_name.nil? # skip if not in tap_migrations list.

      new_tap_user, new_tap_repo, new_tap_new_name = new_tap_name.split("/")
      new_name = if new_tap_new_name
        new_full_name = new_tap_new_name
        new_tap_name = "#{new_tap_user}/#{new_tap_repo}"
        new_tap_new_name
      elsif new_tap_repo
        new_full_name = "#{new_tap_name}/#{name}"
        name
      else
        new_tap_name = tap.name
        new_full_name = "#{new_tap_name}/#{new_tap_user}"
        new_tap_user
      end

      # This means it is a cask
      if Array(report[:DC]).include? full_name
        next unless (HOMEBREW_PREFIX/"Caskroom"/new_name).exist?

        new_tap = Tap.fetch(new_tap_name)
        new_tap.ensure_installed!
        ohai "#{name} has been moved to Homebrew.", <<~EOS
          To uninstall the cask, run:
            brew uninstall --cask --force #{name}
        EOS
        next if (HOMEBREW_CELLAR/new_name.split("/").last).directory?

        ohai "Installing #{new_name}..."
        system HOMEBREW_BREW_FILE, "install", new_full_name
        begin
          unless Formulary.factory(new_full_name).keg_only?
            system HOMEBREW_BREW_FILE, "link", new_full_name, "--overwrite"
          end
        # Rescue any possible exception types.
        rescue Exception => e # rubocop:disable Lint/RescueException
          if Homebrew::EnvConfig.developer?
            require "utils/backtrace"
            onoe "#{e.message}\n#{Utils::Backtrace.clean(e)&.join("\n")}"
          end
        end
        next
      end

      next unless (dir = HOMEBREW_CELLAR/name).exist? # skip if formula is not installed.

      tabs = dir.subdirs.map { |d| Keg.new(d).tab }
      next if tabs.first.tap != tap # skip if installed formula is not from this tap.

      new_tap = Tap.fetch(new_tap_name)
      # For formulae migrated to cask: Auto-install cask or provide install instructions.
      # Check if the migration target is a cask (either in homebrew/cask or any other tap)
      if new_tap.core_cask_tap? || new_tap.cask_tokens.intersect?([new_full_name, new_name])
        migration_message = if new_tap == tap
          "#{full_name} has been migrated from a formula to a cask."
        else
          "#{name} has been moved to #{new_tap_name}."
        end
        if new_tap.installed? && (HOMEBREW_PREFIX/"Caskroom").directory?
          ohai migration_message
          ohai "brew unlink #{name}"
          system HOMEBREW_BREW_FILE, "unlink", name
          ohai "brew cleanup"
          system HOMEBREW_BREW_FILE, "cleanup"
          ohai "brew install --cask #{new_full_name}"
          system HOMEBREW_BREW_FILE, "install", "--cask", new_full_name
          ohai migration_message, <<~EOS
            The existing keg has been unlinked.
            Please uninstall the formula when convenient by running:
              brew uninstall --formula --force #{name}
          EOS
        else
          ohai migration_message, <<~EOS
            To uninstall the formula and install the cask, run:
              brew uninstall --formula --force #{name}
              brew tap #{new_tap_name}
              brew install --cask #{new_full_name}
          EOS
        end
      else
        new_tap.ensure_installed!
        # update tap for each Tab
        tabs.each { |tab| tab.tap = new_tap }
        tabs.each(&:write)
      end
    end
  end

  sig { void }
  def migrate_cask_rename
    Cask::Caskroom.casks.each do |cask|
      Cask::Migrator.migrate_if_needed(cask)
    end
  end

  sig { params(force: T::Boolean, verbose: T::Boolean).void }
  def migrate_formula_rename(force:, verbose:)
    Formula.installed.each do |formula|
      next unless Migrator.needs_migration?(formula)

      oldnames_to_migrate = formula.oldnames.select do |oldname|
        oldname_rack = HOMEBREW_CELLAR/oldname
        next false unless oldname_rack.exist?

        if oldname_rack.subdirs.empty?
          oldname_rack.rmdir_if_possible
          next false
        end

        true
      end
      next if oldnames_to_migrate.empty?

      Migrator.migrate_if_needed(formula, force:)
    end
  end

  private

  sig { returns(Tap) }
  attr_reader :tap

  sig { returns(String) }
  attr_reader :initial_revision

  sig { returns(String) }
  attr_reader :current_revision

  sig { returns(T.nilable(Pathname)) }
  attr_reader :api_names_txt

  sig { returns(T.nilable(Pathname)) }
  attr_reader :api_names_before_txt

  sig { returns(T.nilable(Pathname)) }
  attr_reader :api_dir_prefix

  sig {
    params(api_names_txt: T.nilable(Pathname), api_names_before_txt: T.nilable(Pathname),
           api_dir_prefix: T.nilable(Pathname)).returns(T::Boolean)
  }
  def installed_from_api?(api_names_txt = @api_names_txt, api_names_before_txt = @api_names_before_txt,
                          api_dir_prefix = @api_dir_prefix)
    !api_names_txt.nil? && !api_names_before_txt.nil? && !api_dir_prefix.nil?
  end

  sig { returns(String) }
  def diff
    @diff ||= T.let(nil, T.nilable(String))
    @diff ||= if installed_from_api?
      # Hack `git diff` output with regexes to look like `git diff-tree` output.
      # Yes, I know this is a bit filthy but it saves duplicating the #report logic.
      diff_output = Utils.popen_read("git", "diff", "--no-ext-diff", api_names_before_txt, api_names_txt)
      header_regex = /^(---|\+\+\+) /
      add_delete_characters = ["+", "-"].freeze

      api_dir_prefix_basename = T.must(api_dir_prefix).basename

      diff_hash = diff_output.lines.each_with_object({}) do |line, hash|
        next if line.match?(header_regex)
        next unless add_delete_characters.include?(line[0])

        name = line.chomp.delete_prefix("+").delete_prefix("-")
        file = "#{api_dir_prefix_basename}/#{name}.rb"

        hash[file] ||= 0
        if line.start_with?("+")
          hash[file] += 1
        elsif line.start_with?("-")
          hash[file] -= 1
        end
      end

      diff_hash.filter_map do |file, count|
        if count.positive?
          "A #{file}"
        elsif count.negative?
          "D #{file}"
        end
      end.join("\n")
    else
      Utils.popen_read(
        "git", "-C", tap.path, "diff-tree", "-r", "--name-status", "--diff-filter=AMDR",
        "-M85%", initial_revision, current_revision
      )
    end
  end
end

class ReporterHub
  include Utils::Output::Mixin

  sig { returns(T::Array[Reporter]) }
  attr_reader :reporters

  sig { void }
  def initialize
    @hash = T.let({}, T::Hash[Symbol, T::Array[T.any(String, [String, String])]])
    @reporters = T.let([], T::Array[Reporter])
  end

  sig { params(key: Symbol).returns(T::Array[String]) }
  def select_formula_or_cask(key)
    raise "Unsupported key #{key}" unless [:A, :AC, :D, :DC, :M, :MC, :R, :RC, :T].include?(key)

    T.cast(@hash.fetch(key, []), T::Array[String])
  end

  sig { params(reporter: Reporter, auto_update: T::Boolean).void }
  def add(reporter, auto_update: false)
    @reporters << reporter
    report = reporter.report(auto_update:).reject { |_k, v| v.empty? }
    @hash.update(report) { |_key, oldval, newval| oldval.concat(newval) }
  end

  sig { returns(T::Boolean) }
  def empty?
    @hash.empty?
  end

  sig { params(auto_update: T::Boolean).void }
  def dump(auto_update: false)
    unless Homebrew::EnvConfig.no_update_report_new?
      dump_new_formula_report
      dump_new_cask_report
    end

    dump_deleted_formula_report
    dump_deleted_cask_report

    outdated_formulae = Formula.installed.select(&:outdated?).map(&:name)
    outdated_casks = Cask::Caskroom.casks.select(&:outdated?).map(&:token)
    unless auto_update
      output_dump_formula_or_cask_report "Outdated Formulae", outdated_formulae
      output_dump_formula_or_cask_report "Outdated Casks", outdated_casks
    end
    return if outdated_formulae.blank? && outdated_casks.blank?

    outdated_formulae = outdated_formulae.count
    outdated_casks = outdated_casks.count

    update_pronoun = if (outdated_formulae + outdated_casks) == 1
      "it"
    else
      "them"
    end

    msg = ""

    if outdated_formulae.positive?
      noun = Utils.pluralize("formula", outdated_formulae)
      msg += "#{Tty.bold}#{outdated_formulae}#{Tty.reset} outdated #{noun}"
    end

    if outdated_casks.positive?
      msg += " and " if msg.present?
      msg += "#{Tty.bold}#{outdated_casks}#{Tty.reset} outdated #{Utils.pluralize("cask", outdated_casks)}"
    end

    return if msg.blank?

    puts
    puts "You have #{msg} installed."
    # If we're auto-updating, don't need to suggest commands that we're perhaps
    # already running.
    return if auto_update

    puts <<~EOS
      You can upgrade #{update_pronoun} with #{Tty.bold}brew upgrade#{Tty.reset}
      or list #{update_pronoun} with #{Tty.bold}brew outdated#{Tty.reset}.
    EOS
  end

  private

  sig { void }
  def dump_new_formula_report
    formulae = select_formula_or_cask(:A).sort.reject { |name| installed?(name) }
    return if formulae.blank?

    ohai "New Formulae"
    should_display_descriptions = if Homebrew::EnvConfig.no_install_from_api?
      formulae.size <= 100
    else
      true
    end
    formulae.each do |formula|
      if should_display_descriptions && (desc = description(formula))
        puts "#{formula}: #{desc}"
      else
        puts formula
      end
    end
  end

  sig { void }
  def dump_new_cask_report
    return unless Cask::Caskroom.any_casks_installed?

    casks = select_formula_or_cask(:AC).sort.reject { |name| cask_installed?(name) }
    return if casks.blank?

    ohai "New Casks"
    should_display_descriptions = if Homebrew::EnvConfig.no_install_from_api?
      casks.size <= 100
    else
      true
    end
    casks.each do |cask|
      cask_token = cask.split("/").fetch(-1)
      if should_display_descriptions && (desc = cask_description(cask))
        puts "#{cask_token}: #{desc}"
      else
        puts cask_token
      end
    end
  end

  sig { void }
  def dump_deleted_formula_report
    formulae = select_formula_or_cask(:D).sort.filter_map do |name|
      pretty_uninstalled(name) if installed?(name)
    end

    output_dump_formula_or_cask_report "Deleted Installed Formulae", formulae
  end

  sig { void }
  def dump_deleted_cask_report
    return if Homebrew::SimulateSystem.simulating_or_running_on_linux?

    casks = select_formula_or_cask(:DC).sort.filter_map do |name|
      name = name.split("/").fetch(-1)
      pretty_uninstalled(name) if cask_installed?(name)
    end

    output_dump_formula_or_cask_report "Deleted Installed Casks", casks
  end

  sig { params(title: String, formulae_or_casks: T::Array[String]).void }
  def output_dump_formula_or_cask_report(title, formulae_or_casks)
    return if formulae_or_casks.blank?

    ohai title, Formatter.columns(formulae_or_casks.sort)
  end

  sig { params(formula: String).returns(T::Boolean) }
  def installed?(formula)
    (HOMEBREW_CELLAR/formula.split("/").last).directory?
  end

  sig { params(cask: String).returns(T::Boolean) }
  def cask_installed?(cask)
    (Cask::Caskroom.path/cask).directory?
  end

  sig { returns(T::Array[T.untyped]) }
  def all_formula_json
    return @all_formula_json if @all_formula_json

    @all_formula_json = T.let(nil, T.nilable(T::Array[T.untyped]))
    all_formula_json, = Homebrew::API.fetch_json_api_file "formula.jws.json"
    all_formula_json = T.cast(all_formula_json, T::Array[T.untyped])
    @all_formula_json = all_formula_json
  end

  sig { returns(T::Array[T.untyped]) }
  def all_cask_json
    return @all_cask_json if @all_cask_json

    @all_cask_json = T.let(nil, T.nilable(T::Array[T.untyped]))
    all_cask_json, = Homebrew::API.fetch_json_api_file "cask.jws.json"
    all_cask_json = T.cast(all_cask_json, T::Array[T.untyped])
    @all_cask_json = all_cask_json
  end

  sig { params(formula: String).returns(T.nilable(String)) }
  def description(formula)
    if Homebrew::EnvConfig.no_install_from_api?
      # Skip non-homebrew/core formulae for security.
      return if formula.include?("/")

      begin
        Formula[formula].desc&.presence
      rescue FormulaUnavailableError
        nil
      end
    else
      all_formula_json.find { |f| f["name"] == formula }
                      &.fetch("desc", nil)
                      &.presence
    end
  end

  sig { params(cask: String).returns(T.nilable(String)) }
  def cask_description(cask)
    if Homebrew::EnvConfig.no_install_from_api?
      # Skip non-homebrew/cask formulae for security.
      return if cask.include?("/")

      begin
        Cask::CaskLoader.load(cask).desc&.presence
      rescue Cask::CaskError
        nil
      end
    else
      all_cask_json.find { |f| f["token"] == cask }
                   &.fetch("desc", nil)
                   &.presence
    end
  end
end
