# typed: strict
# frozen_string_literal: true

require "trust"

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
        name = Utils.name_from_full_name(full_name)
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
      old_name = Utils.name_from_full_name(old_full_name)
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
      new_name = Utils.name_from_full_name(new_full_name)
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
      old_name = Utils.name_from_full_name(old_full_name)
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
      new_name = Utils.name_from_full_name(new_full_name)
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
      name = Utils.name_from_full_name(full_name)
      migration_target = tap.tap_migrations[name]
      next if migration_target.nil? # skip if not in tap_migrations list.

      migrated_tap_name = Utils.tap_from_full_name(migration_target)
      new_name = if migrated_tap_name
        new_full_name = Utils.name_from_full_name(migration_target)
        new_tap_name = migrated_tap_name
        new_full_name
      elsif migration_target.include?("/")
        new_tap_name = migration_target
        new_full_name = "#{new_tap_name}/#{name}"
        name
      else
        new_tap_name = tap.name
        new_full_name = "#{new_tap_name}/#{migration_target}"
        migration_target
      end

      # This means it is a cask
      if Array(report[:DC]).include? full_name
        next unless (HOMEBREW_PREFIX/"Caskroom"/name).exist?

        new_tap = Tap.fetch(new_tap_name)
        next unless ensure_trusted_tap_installed!(name, new_name, new_tap)

        ohai "#{name} has been moved to Homebrew.", <<~EOS
          To uninstall the cask, run:
            brew uninstall --cask --force #{name}
        EOS
        next if (HOMEBREW_CELLAR/Utils.name_from_full_name(new_name)).directory?

        ohai "Installing #{new_name}..."
        begin
          system HOMEBREW_BREW_FILE, "install", "--overwrite", new_full_name
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
        next unless ensure_trusted_tap_installed!(name, new_name, new_tap)

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

  sig { params(name: String, new_name: String, new_tap: Tap).returns(T::Boolean) }
  def ensure_trusted_tap_installed!(name, new_name, new_tap)
    return true if new_tap.installed?

    unless Homebrew::Trust.trusted_tap?(new_tap)
      new_bare_name = Utils.name_from_full_name(new_name)
      new_full_name = "#{new_tap.name}/#{new_bare_name}"
      # `brew migrate` only migrates renamed packages, so a tap-only migration
      # (unchanged name) needs a reinstall from the new tap instead.
      complete_command = if new_bare_name == name
        "brew reinstall #{name}"
      else
        "brew migrate #{name}"
      end
      opoo <<~EOS
        Not automatically tapping #{new_tap} to migrate #{name} as it is not a
        trusted tap. To complete the migration yourself, run:
          brew tap #{new_tap}
          brew trust #{new_full_name}
          #{complete_command}
      EOS
      return false
    end

    new_tap.ensure_installed!
    true
  end

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
