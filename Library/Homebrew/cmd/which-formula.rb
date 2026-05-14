# typed: strict
# frozen_string_literal: true

# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

require "abstract_command"
require "api"
require "caveats"
require "did_you_mean"
require "formulary"
require "utils/curl"
require "utils/output"

module Homebrew
  module Cmd
    class WhichFormula < AbstractCommand
      ENDPOINT = "internal/executables.txt"
      DATABASE_FILE = T.let((Homebrew::API::HOMEBREW_CACHE_API/ENDPOINT).freeze, Pathname)

      include Utils::Output::Mixin

      cmd_args do
        description <<~EOS
          Show which formula(e) provides the given command.
        EOS
        switch "--explain",
               description: "Output explanation of how to get <command> by installing one of the providing formulae."
        switch "--skip-update",
               description: "Skip updating the executables database if any version exists on disk, no matter how old."
        named_args :command, min: 1
      end

      sig { override.void }
      def run
        download_and_cache_executables_file!(skip_update: args.skip_update?)

        args.named.each_with_index do |command, index|
          puts if index.positive?

          formulae = database[command]
          if formulae.blank?
            ofail no_match_message(command)
            next
          end

          oh1 command
          if args.explain?
            print_explanation(command, formulae)
          else
            formulae.each { |name| puts decorate(name, command:) }
            warn_if_shadowed(command, formulae)
          end
        end
      end

      private

      sig { returns(T::Hash[String, T::Array[String]]) }
      def database
        @database ||= T.let(parse_database, T.nilable(T::Hash[String, T::Array[String]]))
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def parse_database
        index = T.let({}, T::Hash[String, T::Array[String]])
        return index unless DATABASE_FILE.exist?

        DATABASE_FILE.each_line do |line|
          formula, cmds_text = line.chomp.split(":", 2)
          next if formula.blank?
          next if cmds_text.blank?

          formula = formula.sub(/\(.*\)\z/, "")
          cmds_text.split.each { |cmd| (index[cmd] ||= []) << formula }
        end
        index
      end

      sig { params(command: String).returns(String) }
      def no_match_message(command)
        message = "No formula provides the binary \"#{command}\"."
        suggestions = DidYouMean::SpellChecker.new(dictionary: database.keys).correct(command)
        return message if suggestions.blank?

        suggestion_text = suggestions.to_sentence(two_words_connector: " or ", last_word_connector: " or ")
        "#{message} Did you mean #{suggestion_text}?"
      end

      sig { params(name: String, command: String).returns(String) }
      def decorate(name, command:)
        formula = Formulary.factory(name)
        decorated = pretty_install_status(
          name, installed: formula.any_version_installed?, outdated: formula.outdated?
        )
        decorated += " [Linked]" if formula_provides_linked_binary?(formula, command)
        decorated
      rescue FormulaUnavailableError, TapFormulaUnavailableError
        name
      end

      sig { params(formula: Formula, command: String).returns(T::Boolean) }
      def formula_provides_linked_binary?(formula, command)
        linked_keg = formula.linked_keg
        return false unless linked_keg.directory?

        (linked_keg/"bin"/command).exist? || (linked_keg/"sbin"/command).exist?
      end

      sig { params(command: String, formulae: T::Array[String]).void }
      def warn_if_shadowed(command, formulae)
        return if Homebrew::EnvConfig.no_path_shadow_check?
        return unless formulae.any? { |name| any_version_installed?(name) }

        resolved = which(command, ORIGINAL_PATHS)
        return if resolved.nil?
        return if resolved.to_s.start_with?("#{HOMEBREW_PREFIX}/")

        opoo "#{command} is shadowed by #{resolved} earlier in your PATH."
      end

      sig { params(command: String, formulae: T::Array[String]).void }
      def print_explanation(command, formulae)
        uninstalled = formulae.reject { |name| any_version_installed?(name) }
        if uninstalled.empty?
          puts "The program '#{command}' is already provided by an installed formula."
          return
        end

        if uninstalled.length == 1
          puts "The program '#{command}' is currently not installed. You can install it by typing:"
          puts "  brew install #{uninstalled.first}"
        else
          puts "The program '#{command}' can be found in the following formulae:"
          uninstalled.each { |name| puts "  * #{name}" }
          puts "Try: brew install <selected formula>"
        end
      end

      sig { params(name: String).returns(T::Boolean) }
      def any_version_installed?(name)
        (HOMEBREW_CELLAR/name).directory?
      end

      sig { params(skip_update: T::Boolean).void }
      def download_and_cache_executables_file!(skip_update:)
        return if DATABASE_FILE.exist? && !DATABASE_FILE.empty? && (skip_update || fresh?)

        url = "#{HOMEBREW_API_DEFAULT_DOMAIN}/#{ENDPOINT}"
        DATABASE_FILE.dirname.mkpath

        curl_args = [
          "--compressed",
          "--speed-limit", ENV.fetch("HOMEBREW_CURL_SPEED_LIMIT"),
          "--speed-time", ENV.fetch("HOMEBREW_CURL_SPEED_TIME"),
          "--remote-time",
          "--user-agent", ENV.fetch("HOMEBREW_USER_AGENT_CURL")
        ]
        if ENV["CI"]
          curl_args.push("--retry", "3", "--retry-delay", "0", "--retry-max-time", "60")
        else
          curl_args.push("--max-time", "10")
        end

        Utils::Curl.curl_download(*curl_args, url, to: DATABASE_FILE, show_error: false)
        FileUtils.touch(DATABASE_FILE)

        system("git", "config", "--file=#{HOMEBREW_REPOSITORY}/.git/config",
               "--bool", "homebrew.commandnotfound", "true",
               out: File::NULL, err: File::NULL)
      end

      sig { returns(T::Boolean) }
      def fresh?
        auto_update_secs = Homebrew::EnvConfig.api_auto_update_secs.to_i
        (Time.now - DATABASE_FILE.mtime) < auto_update_secs
      end
    end
  end
end
