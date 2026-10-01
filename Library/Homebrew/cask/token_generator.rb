# typed: strict
# frozen_string_literal: true

require "system_command"

module Cask
  # Generates a cask token from an application name or bundle path, following
  # the token conventions described in the Cask Cookbook.
  module TokenGenerator
    extend SystemCommand::Mixin

    EXPANDED_SYMBOLS = T.let({
      "+" => "plus",
      "@" => "at",
    }.freeze, T::Hash[String, String])

    # Trailing patterns on app names that could be mistaken for version numbers etc.
    # but should be preserved.
    PRESERVE_TRAILING_PATS = T.let([
      /id3/i,
      /mp3/i,
      /3[\s-]*d/i,
      /diff3/i,
      /\A[^\d]+\+\Z/i,
    ].freeze, T::Array[Regexp])
    PRESERVE_TRAILING_PAT = /(?:#{Regexp.union(PRESERVE_TRAILING_PATS)})\Z/i

    # These patterns are applied repeatedly to the end of the app name until none
    # matches, after word breaks have been inserted at CamelCase and snake_case
    # transitions.
    REMOVE_TRAILING_PATS = T.let([
      # spaces
      /\s+/i,

      # generic terms
      /\bapp/i,
      /\b(?:quick[\s-]*)?launcher/i,

      # "mac", "for mac", "for OS X", "macOS", "for macOS".
      /\b(?:for)?[\s-]*mac(?:intosh|OS)?/i,
      /\b(?:for)?[\s-]*os[\s-]*x/i,

      # hardware designations such as "for x86", "32-bit", "ppc"
      /(?:\bfor\s*)?x.?86/i,
      /(?:\bfor\s*)?\bppc/i,
      /(?:\bfor\s*)?\barm(?:64|v\d+)?/i,
      /(?:\bfor\s*)?\d+.?bits?/i,

      # frameworks
      /\b(?:for)?[\s-]*(?:oracle|apple|sun)*[\s-]*(?:jvm|java|jre)/i,
      /\bgtk/i,
      /\bqt/i,
      /\bwx/i,
      /\bcocoa/i,

      # localizations
      /en\s*-\s*us/i,

      # trailing punctuation
      /[^a-z0-9]+/i,

      # release qualifiers, which are words rather than bare version numbers
      /\b(?:version|alpha|beta|gamma|release|release.?candidate)(?:[\s.\d-]*\d[\s.\d-]*)?/i,
    ].freeze, T::Array[Regexp])
    REMOVE_TRAILING_PAT = /(?<=.)(?:#{Regexp.union(REMOVE_TRAILING_PATS)})\Z/i

    sig { params(app: String).returns(String) }
    def self.generate(app)
      token_for(simplified_app_name(app))
    end

    sig { params(app: String).returns(String) }
    def self.simplified_app_name(app)
      name = english_app_name(app.dup.force_encoding(Encoding::UTF_8))
      name = Pathname(name).basename.to_s if Pathname(name).exist?
      name = decompose_to_ascii(name).sub(/\.app\Z/i, "")
      remove_trailing_strings(name)
    end

    sig { params(app_name: String).returns(String) }
    def self.token_for(app_name)
      token = app_name.downcase
      EXPANDED_SYMBOLS.each do |symbol, word|
        token = token.gsub(symbol, " #{word} ")
      end
      token = token.sub(/ +\Z/, "")
                   .gsub(/ +/, "-")
                   .gsub(/[^a-z0-9-]+/, "")
                   .gsub(/--+/, "-")
                   .gsub(/\A-+|-+\z/, "")
      raise UsageError, "Could not determine a token from '#{app_name}'." if token.empty?

      token
    end

    sig { params(token: String).returns(T::Array[String]) }
    def self.warnings(token)
      warnings = []
      if token.sub(/@.*\z/, "").match?(/\d/)
        warnings << "'#{token}' contains digits. If they are a version number, " \
                    "remove them from the token and file name."
      end
      warnings
    end

    # Attempt to find an English app name for an app bundle whose name on disk
    # contains non-ASCII characters.
    sig { params(app: String).returns(String) }
    def self.english_app_name(app)
      return app if app.ascii_only?

      app_path = Pathname(app)
      return app unless app_path.exist?

      candidates = [
        bundle_info_string(app_path, "CFBundleDisplayName"),
        bundle_info_string(app_path, "CFBundleName"),
        localized_app_name(app_path),
        bundle_info_string(app_path, "CFBundleExecutable"),
      ]
      candidates.compact.find(&:ascii_only?) || app
    end
    private_class_method :english_app_name

    sig { params(app_path: Pathname, key: String).returns(T.nilable(String)) }
    def self.bundle_info_string(app_path, key)
      info_plist = app_path/"Contents/Info.plist"
      return unless info_plist.file?

      result = system_command "/usr/libexec/PlistBuddy",
                              args:         ["-c", "Print #{key}", info_plist],
                              print_stderr: false
      return unless result.success?

      result.stdout.lines.first&.force_encoding(Encoding::UTF_8)&.chomp
    end
    private_class_method :bundle_info_string

    sig { params(app_path: Pathname).returns(T.nilable(String)) }
    def self.localized_app_name(app_path)
      strings_file = app_path/"Contents/Resources/en.lproj/InfoPlist.strings"
      strings_file = app_path/"Contents/Resources/English.lproj/InfoPlist.strings" unless strings_file.exist?
      return unless strings_file.exist?

      name_line = File.open(strings_file, "r:UTF-16LE:UTF-8") do |fh|
        fh.readlines.grep(/^CFBundle(?:Display)?Name\s*=\s*/).first
      end
      name_line&.[](/\ACFBundle(?:Display)?Name\s*=\s*"(.*)";\Z/, 1)
    end
    private_class_method :localized_app_name

    # Crudely (and incorrectly) decompose extended Latin characters to ASCII.
    sig { params(name: String).returns(String) }
    def self.decompose_to_ascii(name)
      name = name.tr("·‧・･", "-")
      return name if name.ascii_only?

      name.unicode_normalize(:nfkd).each_char.select(&:ascii_only?).join
    end
    private_class_method :decompose_to_ascii

    # Only terms separated by a space are removed: a term joined to the name,
    # as in `WhatsApp` or `PlayOnMac`, is part of it.
    sig { params(name: String).returns(String) }
    def self.remove_trailing_strings(name)
      name = name.tr("_", " ")
      loop do
        break if !name.match?(REMOVE_TRAILING_PAT) || name.match?(PRESERVE_TRAILING_PAT)

        name = name.sub(REMOVE_TRAILING_PAT, "")
      end
      name
    end
    private_class_method :remove_trailing_strings
  end
end
