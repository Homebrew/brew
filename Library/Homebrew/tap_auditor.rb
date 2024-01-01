# typed: true
# frozen_string_literal: true

module Homebrew
  # Auditor for checking common violations in {Tap}s.
  #
  # @api private
  class TapAuditor
    attr_reader :name, :path, :formula_names, :formula_aliases, :cask_tokens,
                :tap_audit_exceptions, :tap_style_exceptions, :tap_pypi_formula_mappings, :problems

    sig { params(tap: Tap, strict: T.nilable(T::Boolean)).void }
    def initialize(tap, strict:)
      Homebrew.with_no_api_env do
        @name                      = tap.name
        @path                      = tap.path
        @cask_tokens               = tap.cask_tokens
        @tap_audit_exceptions      = tap.audit_exceptions
        @tap_style_exceptions      = tap.style_exceptions
        @tap_pypi_formula_mappings = tap.pypi_formula_mappings
        @problems                  = []

        @formula_aliases = tap.aliases.map do |formula_alias|
          formula_alias.split("/").last
        end
        @formula_names = tap.formula_names.map do |formula_name|
          formula_name.split("/").last
        end
      end
    end

    sig { void }
    def audit
      audit_json_files
      audit_tap_formula_lists
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
    end

    sig { params(message: String).void }
    def problem(message)
      @problems << ({ message: message, location: nil, corrected: false })
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

      list = list.keys if list.is_a? Hash
      invalid_formulae_casks = list.select do |formula_or_cask_name|
        formula_names.exclude?(formula_or_cask_name) &&
          formula_aliases.exclude?(formula_or_cask_name) &&
          cask_tokens.exclude?("#{@name}/#{formula_or_cask_name}")
      end

      return if invalid_formulae_casks.empty?

      problem <<~EOS
        #{list_file}.json references
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
