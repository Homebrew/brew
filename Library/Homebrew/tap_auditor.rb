# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  # Auditor for checking common violations in {Tap}s.
  class TapAuditor
    attr_reader :name, :path, :formula_names, :formula_aliases, :formula_renames, :cask_tokens,
                :tap_audit_exceptions, :tap_style_exceptions, :tap_pypi_formula_mappings, :problems

    sig { params(tap: Tap, strict: T.nilable(T::Boolean)).void }
    def initialize(tap, strict:)
      Homebrew.with_no_api_env do
        tap.clear_cache if Homebrew::EnvConfig.automatically_set_no_install_from_api?
        @name                      = tap.name
        @path                      = tap.path
        @tap_audit_exceptions      = tap.audit_exceptions
        @tap_style_exceptions      = tap.style_exceptions
        @tap_pypi_formula_mappings = tap.pypi_formula_mappings
        @tap_autobump              = tap.autobump
        @tap_official              = tap.official?
        @problems                  = []

        @cask_tokens = tap.cask_tokens.map do |cask_token|
          cask_token.split("/").last
        end
        @formula_aliases = tap.aliases.map do |formula_alias|
          formula_alias.split("/").last
        end
        @formula_renames = tap.formula_renames
        @formula_names = tap.formula_names.map do |formula_name|
          formula_name.split("/").last
        end
      end
    end

    sig { void }
    def audit
      audit_json_files
      audit_tap_formula_lists
      audit_aliases_renames_duplicates
    end

    sig { void }
    def audit_json_files
      json_patterns = Tap::HOMEBREW_TAP_JSON_FILES.map { |pattern| @path/pattern }
      Pathname.glob(json_patterns).each do |file|
        JSON.parse file.read
      rescue JSON::ParserError
        problem "#{file.to_s.delete_prefix("#{@path}/")} contains invalid JSON"
      end
    end

    sig { void }
    def audit_tap_formula_lists
      check_formula_list_directory "audit_exceptions", @tap_audit_exceptions
      check_formula_list_directory "style_exceptions", @tap_style_exceptions
      check_formula_list "pypi_formula_mappings", @tap_pypi_formula_mappings
      check_formula_list "formula_renames", @formula_renames.values
      check_formula_list ".github/autobump.txt", @tap_autobump unless @tap_official
    end

    sig { void }
    def audit_aliases_renames_duplicates
      duplicates = formula_aliases & formula_renames.keys
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
      list_file += ".json" if File.extname(list_file).empty?
      unless [Hash, Array].include? list.class
        problem <<~EOS
          #{list_file} should contain a JSON array
          of formula names or a JSON object mapping formula names to values
        EOS
        return
      end

      list = list.keys if list.is_a? Hash
      invalid_formulae_casks = list.select do |formula_or_cask_name|
        formula_names.exclude?(formula_or_cask_name) &&
          formula_aliases.exclude?(formula_or_cask_name) &&
          cask_tokens.exclude?(formula_or_cask_name)
      end

      return if invalid_formulae_casks.empty?

      problem <<~EOS
        #{list_file} references
        formulae or casks that are not found in the #{@name} tap.
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
