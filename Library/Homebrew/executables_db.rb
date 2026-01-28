# typed: strict
# frozen_string_literal: true

# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

require "formula"
require "formulary"
require "tap"
require "utils/output"

module Homebrew
  # ExecutablesDB represents a DB associating formulae to the binaries they
  # provide.
  class ExecutablesDB
    include Utils::Output::Mixin

    sig { returns(T::Hash[String, FormulaEntry]) }
    attr_accessor :exes

    sig { returns(Changes) }
    attr_reader :changes

    sig { returns(Pathname) }
    attr_reader :root

    DB_LINE_REGEX = /^(?<name>.*?)(?:\((?<version>.*)\)):(?<exes_line>.*)?$/

    class FormulaEntry < T::Struct
      const :version, String
      const :binaries, T::Array[String]
    end

    class Changes
      TYPES = [:add, :remove, :update, :version_bump].freeze

      sig { returns(T::Set[String]) }
      attr_accessor :add, :remove, :update, :version_bump

      sig { void }
      def initialize
        @add = T.let(Set.new, T::Set[String])
        @remove = T.let(Set.new, T::Set[String])
        @update = T.let(Set.new, T::Set[String])
        @version_bump = T.let(Set.new, T::Set[String])
      end

      sig { returns(T::Boolean) }
      def changed?
        add.any? || remove.any? || update.any? || version_bump.any?
      end
    end

    # initialize a new DB with the given filename. The file will be used to
    # populate the DB if it exists. It'll be created or overridden when saving the
    # DB.
    # @see #save!
    sig { params(filename: String).void }
    def initialize(filename)
      @filename = filename
      @root = T.let(Pathname.new(@filename).parent, Pathname)
      @exes = T.let({}, T::Hash[String, FormulaEntry])
      # keeps track of things that changed in the DB between its creation and
      # each {#save!} call. This is used to generate commit messages
      @changes = T.let(Changes.new, Changes)

      return unless File.file? @filename

      File.new(@filename).each do |line|
        matches = line.match DB_LINE_REGEX
        next unless matches

        name = T.must(matches[:name])
        version = T.must(matches[:version])
        binaries = matches[:exes_line]&.split || []

        @exes[name] ||= FormulaEntry.new(version:, binaries:)
      end
    end

    sig { returns(T::Array[String]) }
    def formula_names
      @exes.keys
    end

    sig { returns(T::Boolean) }
    def changed?
      @changes.changed?
    end

    # update the DB with the installed formulae
    # @see #save!
    sig {
      params(
        update_existing: T::Boolean,
        install_missing: T::Boolean,
        max_downloads:   T.nilable(Integer),
        eval_all:        T::Boolean,
      ).void
    }
    def update!(update_existing: false, install_missing: false, max_downloads: nil, eval_all: false)
      downloads = 0
      disabled_formulae = []

      # Evaluate only the core tap by default.
      taps = eval_all ? Tap.each.to_a : [CoreTap.instance]
      taps.each do |tap|
        tap.formula_files_by_name.each_key do |name|
          f = Formulary.factory("#{tap}/#{name}")

          break if max_downloads.present? && downloads > max_downloads.to_i

          name = f.full_name

          if f.disabled?
            disabled_formulae << name
            next
          end

          update_formula = missing_formula?(f) || (update_existing && outdated_formula?(f))

          # Install unbottled formulae if they should be added/updated
          if !f.bottled? && install_missing && update_formula
            downloads += 1
            ohai "Installing #{f}"
            system HOMEBREW_BREW_FILE, "install", "--formula", f.to_s
          end

          # We don't need to worry about updating outdated versions unless update_existing is true
          if f.latest_version_installed?
            update_installed_formula f
          elsif f.bottled? && update_formula
            downloads += 1
            update_bottled_formula f
          end

          # renamed formulae
          f.oldnames.each do |oldname|
            mv oldname, name if @exes[oldname]
          end

          # aliased formulae
          f.aliases.each do |a|
            mv a, name if @exes[a]
          end
        end
      end

      removed = (@exes.keys - Formula.full_names) | disabled_formulae
      removed.each do |name|
        next unless @exes.key?(name)

        @exes.delete name
        @changes.remove << name
      end
      nil
    end

    # save the DB in the underlying file
    sig { void }
    def save!
      ordered_db = @exes.map do |formula, entry|
        version_string = "(#{entry.version})"
        "#{formula}#{version_string}:#{entry.binaries.join(" ")}\n"
      end.sort

      File.open(@filename, "w") do |f|
        ordered_db.each do |line|
          f.write(line)
        end
      end
    end

    private

    sig { params(old: String, new: String).void }
    def mv(old, new)
      return unless (old_entry = @exes[old])

      unless @exes[new]
        @exes[new] = old_entry
        @changes.add << new
      end
      @exes.delete old
      @changes.remove << old
      puts "Moving #{old} => #{new}"
    end

    sig { params(formula: Formula).returns(T::Boolean) }
    def missing_formula?(formula)
      !@exes.key? formula.full_name
    end

    sig { params(formula: Formula).returns(T::Boolean) }
    def outdated_formula?(formula)
      return true unless (entry = @exes[formula.full_name])

      formula.pkg_version.to_s != entry.version
    end

    sig { params(formula: Formula, prefix: Pathname).void }
    def update_formula_binaries_from_prefix(formula, prefix = T.unsafe(nil))
      prefix ||= formula.prefix

      binaries = Set.new

      Dir["#{prefix}/{bin,sbin}/*"].each do |file|
        binaries << File.basename(file).to_s if File.executable? file
      end

      update_formula_binaries(formula, binaries)
    end

    sig { params(formula: Formula, binaries: T::Set[String]).void }
    def update_formula_binaries(formula, binaries)
      name = formula.full_name
      version = formula.pkg_version.to_s
      binaries = binaries.to_a.sort

      if missing_formula? formula
        @changes.add << name
      elsif (formula_entry = @exes[name]) && formula_entry.binaries != binaries
        @changes.update << name
      elsif outdated_formula? formula
        @changes.version_bump << name
      end

      @exes[name] = FormulaEntry.new(version:, binaries:)
    end

    # update the binaries of {formula}, assuming it's installed
    sig { params(formula: Formula).void }
    def update_installed_formula(formula)
      update_formula_binaries_from_prefix formula
    end

    # Add a formula's binaries from its bottle
    sig { params(formula: Formula).void }
    def update_bottled_formula(formula)
      return unless (formula_bottle = formula.bottle)

      formula_bottle.fetch
      path = formula_bottle.resource.cached_download.to_s
      content = Utils.popen_read("tar", "tzvf", path, "*/bin/*", "*/sbin/*")
      binaries = Set.new
      prefix = formula.prefix.relative_path_from(HOMEBREW_CELLAR).to_s
      binpath_re = %r{^#{prefix}/s?bin/}
      content.each_line do |line|
        # skip directories and non-executable files
        # 'l' = symlink, '-' = regular file
        next unless /^[l-]r.x/.match?(line)

        # ignore symlink targets
        line = line.chomp.sub(/\s+->.+$/, "")
        path = line.split(/\s+/).last
        next unless binpath_re.match?(path)

        binaries << Pathname.new(path).basename.to_s
      end

      update_formula_binaries formula, binaries
    end
  end
end
