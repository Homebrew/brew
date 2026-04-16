# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    # Shared helpers for reading `@api public/internal/private` annotations
    # from source files at RuboCop runtime. Results are cached at the class
    # level so each file is parsed at most once per RuboCop invocation.
    module ApiAnnotationHelper
      # Taps that enforce stricter public API rules.
      OFFICIAL_TAPS = T.let(%w[
        homebrew-core
        homebrew-cask
      ].freeze, T::Array[String])

      # Source files whose `@api` annotations define the public API surface.
      API_SOURCE_FILES = T.let(%w[
        formula.rb
        cask/cask.rb
        cask/dsl.rb
      ].freeze, T::Array[String])

      # Methods documented in docs/Formula-Cookbook.md mapped to their
      # defining source files (relative to Library/Homebrew/).
      # Validated by `github_actions_utils/public_api_check.rb`
      # against rubydoc links in `docs/Formula-Cookbook.md`.
      FORMULA_COOKBOOK_METHODS = T.let({
        "cd"                    => "extend/pathname.rb",
        "change_make_var!"      => "utils/string_inreplace_extension.rb",
        "compatibility_version" => "formula.rb",
        "conflicts_with"        => "formula.rb",
        "depends_on"            => "formula.rb",
        "deprecated_option"     => "formula.rb",
        "desc"                  => "formula.rb",
        "env_script_all_files"  => "extend/pathname.rb",
        "fails_with"            => "formula.rb",
        "head"                  => "formula.rb",
        "homepage"              => "formula.rb",
        "install_symlink"       => "extend/pathname.rb",
        "keg_only"              => "formula.rb",
        "libexec"               => "formula.rb",
        "license"               => "formula.rb",
        "option"                => "formula.rb",
        "patch"                 => "formula.rb",
        "resource"              => "formula.rb",
        "revision"              => "formula.rb",
        "sha256"                => "formula.rb",
        "stable"                => "formula.rb",
        "test"                  => "formula.rb",
        "testpath"              => "formula.rb",
        "url"                   => "formula.rb",
        "uses_from_macos"       => "formula.rb",
        "version"               => "formula.rb",
        "version_scheme"        => "formula.rb",
        "write_env_script"      => "extend/pathname.rb",
        "write_exec_script"     => "extend/pathname.rb",
        "write_jar_script"      => "extend/pathname.rb",
      }.freeze, T::Hash[String, String])

      # Methods documented in docs/Cask-Cookbook.md mapped to their
      # defining source files (relative to Library/Homebrew/).
      # Validated by `github_actions_utils/public_api_check.rb`
      # against `@api public` annotations in cask source files.
      CASK_COOKBOOK_METHODS = T.let({
        "after_comma"          => "cask/dsl/version.rb",
        "app"                  => "cask/dsl.rb",
        "appdir"               => "cask/dsl.rb",
        "arch"                 => "cask/dsl.rb",
        "artifact"             => "cask/dsl.rb",
        "auto_updates"         => "cask/dsl.rb",
        "before_comma"         => "cask/dsl/version.rb",
        "binary"               => "cask/dsl.rb",
        "caveats"              => "cask/dsl.rb",
        "chomp"                => "cask/dsl/version.rb",
        "conflicts_with"       => "cask/dsl.rb",
        "container"            => "cask/dsl.rb",
        "csv"                  => "cask/dsl/version.rb",
        "depends_on"           => "cask/dsl.rb",
        "deprecate!"           => "cask/dsl.rb",
        "desc"                 => "cask/dsl.rb",
        "disable!"             => "cask/dsl.rb",
        "dots_to_hyphens"      => "cask/dsl/version.rb",
        "font"                 => "cask/dsl.rb",
        "homepage"             => "cask/dsl.rb",
        "hyphens_to_dots"      => "cask/dsl/version.rb",
        "installer"            => "cask/dsl.rb",
        "language"             => "cask/dsl.rb",
        "livecheck"            => "cask/dsl.rb",
        "major"                => "cask/dsl/version.rb",
        "major_minor"          => "cask/dsl/version.rb",
        "major_minor_patch"    => "cask/dsl/version.rb",
        "manpage"              => "cask/dsl.rb",
        "minor"                => "cask/dsl/version.rb",
        "minor_patch"          => "cask/dsl/version.rb",
        "name"                 => "cask/dsl.rb",
        "no_autobump!"         => "cask/dsl.rb",
        "no_dividers"          => "cask/dsl/version.rb",
        "no_dots"              => "cask/dsl/version.rb",
        "no_hyphens"           => "cask/dsl/version.rb",
        "no_underscores"       => "cask/dsl/version.rb",
        "patch"                => "cask/dsl/version.rb",
        "pkg"                  => "cask/dsl.rb",
        "postflight"           => "cask/dsl.rb",
        "preflight"            => "cask/dsl.rb",
        "rename"               => "cask/dsl.rb",
        "service"              => "cask/dsl.rb",
        "sha256"               => "cask/dsl.rb",
        "stage_only"           => "cask/dsl.rb",
        "staged_path"          => "cask/dsl.rb",
        "suite"                => "cask/dsl.rb",
        "to_s"                 => "cask/cask.rb",
        "token"                => "cask/cask.rb",
        "uninstall"            => "cask/dsl.rb",
        "uninstall_postflight" => "cask/dsl.rb",
        "uninstall_preflight"  => "cask/dsl.rb",
        "url"                  => "cask/dsl.rb",
        "version"              => "cask/dsl.rb",
        "zap"                  => "cask/dsl.rb",
      }.freeze, T::Hash[String, String])

      # Returns the set of method names annotated with a given `@api` level
      # (e.g. `"internal"`, `"private"`, `"public"`) in the given Ruby source file.
      sig { params(source_path: String, level: String).returns(T::Set[String]) }
      def self.methods_with_api_level(source_path, level)
        @api_method_cache = T.let(@api_method_cache, T.nilable(T::Hash[String, T::Set[String]]))
        @api_method_cache ||= {}
        cache_key = "#{source_path}:#{level}"
        return @api_method_cache.fetch(cache_key) if @api_method_cache.key?(cache_key)

        methods = T.let(Set.new, T::Set[String])
        return methods unless File.exist?(source_path)

        lines = File.readlines(source_path)
        lines.each_with_index do |line, idx|
          next if line.strip != "# @api #{level}"

          # Scan forward up to 5 lines for a def, attr_reader, or delegate
          (1..5).each do |offset|
            target_line = lines[idx + offset]&.strip
            break if target_line.blank?

            m = target_line.match(/\A(?:def\s+(?:self\.)?|attr_reader\s+:|attr_accessor\s+:)(\w+[!?]?)/) ||
                target_line.match(/\Adelegate\s+(\w+[!?]?):/)
            if m
              methods.add(m[1].to_s)
              break
            end
          end
        end

        @api_method_cache[cache_key] = methods.freeze
        methods
      end

      # Returns the Homebrew library root path (parent of rubocops/).
      sig { returns(String) }
      def self.homebrew_dir
        File.expand_path("../..", __dir__)
      end
    end
  end
end
