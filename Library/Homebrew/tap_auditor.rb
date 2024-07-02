# typed: true
# frozen_string_literal: true

module Homebrew
  # Auditor for checking common violations in {Tap}s.
  class TapAuditor
    sig { returns(Tap) }
    attr_reader :tap

    attr_reader :problems

    sig { params(tap: Tap, strict: T.nilable(T::Boolean)).void }
    def initialize(tap, strict: nil)
      @tap = tap
      @problems = []
    end

    sig { void }
    def audit
      Homebrew.with_no_api_env do
        audit_json_files
        audit_ruby_files
        audit_tap_formula_lists
        audit_aliases_renames_duplicates
      end
    end

    sig { void }
    def audit_json_files
      json_patterns = Tap::HOMEBREW_TAP_JSON_FILES.map { |pattern| tap.path/pattern }
      Pathname.glob(json_patterns).each do |file|
        JSON.parse file.read
      rescue JSON::ParserError
        problem "#{file.to_s.delete_prefix("#{tap.path}/")} contains invalid JSON"
      end
    end

    sig { void }
    def audit_ruby_files
      stray_ruby_files = tap.path.glob("**/*.rb", File::FNM_DOTMATCH)

      stray_ruby_files -= tap.command_files
      stray_ruby_files.reject! { _1.ascend.any?(tap.command_dir) }

      # Allow mixed formula/cask taps except for core taps.
      stray_ruby_files -= tap.cask_files unless tap.core_tap?
      stray_ruby_files -= tap.formula_files unless tap.core_cask_tap?

      return if stray_ruby_files.none?

      problem "Ruby files in wrong location:\n#{stray_ruby_files.map(&:to_s).join("\n")}"
    end

    sig { void }
    def audit_tap_formula_lists
      check_formula_list_directory "audit_exceptions", tap.audit_exceptions
      check_formula_list_directory "style_exceptions", tap.style_exceptions
      check_formula_list "pypi_formula_mappings", tap.pypi_formula_mappings
    end

    sig { void }
    def audit_aliases_renames_duplicates
      formula_aliases = tap.aliases.map do |formula_alias|
        formula_alias.split("/").last
      end

      duplicates = formula_aliases & tap.formula_renames.keys
      return if duplicates.none?

      problem "The following should either be an alias or a rename, not both: #{duplicates.to_sentence}"
    end

    sig { params(message: String).void }
    def problem(message)
      @problems << ({ message:, location: nil, corrected: false })
    end

    private

    sig { params(list_file: String, list: T.untyped).void }
    def check_formula_list(list_file, list)
      unless [Hash, Array].include? list.class
        problem <<~EOS
          #{list_file}.json should contain a JSON array
          of formula names or a JSON object mapping formula names to values
        EOS
        return
      end

      cask_tokens = tap.cask_tokens.map do |cask_token|
        cask_token.split("/").last
      end

      formula_aliases = tap.aliases.map do |formula_alias|
        formula_alias.split("/").last
      end

      formula_names = tap.formula_names.map do |formula_name|
        formula_name.split("/").last
      end

      list = list.keys if list.is_a? Hash
      invalid_formulae_casks = list.select do |formula_or_cask_name|
        formula_names.exclude?(formula_or_cask_name) &&
          formula_aliases.exclude?(formula_or_cask_name) &&
          cask_tokens.exclude?(formula_or_cask_name)
      end

      return if invalid_formulae_casks.empty?

      problem <<~EOS
        #{list_file}.json references
        formulae or casks that are not found in the #{tap.name} tap.
        Invalid formulae or casks: #{invalid_formulae_casks.join(", ")}
      EOS
    end

    sig { params(directory_name: String, lists: Hash).void }
    def check_formula_list_directory(directory_name, lists)
      lists.each do |list_name, list|
        check_formula_list "#{directory_name}/#{list_name}", list
      end
    end
  end
end
