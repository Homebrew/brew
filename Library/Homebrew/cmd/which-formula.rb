# typed: strict
# frozen_string_literal: true

# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

require "abstract_command"
require "api"

module Homebrew
  module Cmd
    class WhichFormula < AbstractCommand
      ENDPOINT = "internal/executables.txt"
      DATABASE_FILE = T.let((Homebrew::API::HOMEBREW_CACHE_API/ENDPOINT).freeze, Pathname)

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
        # NOTE: It probably doesn't make sense to use that on multiple commands since
        # each one might print multiple formulae
        args.named.each do |command|
          which_formula command, explain: args.explain?, skip_update: args.skip_update?
        end
      end

      sig { params(skip_update: T::Boolean).void }
      def download_and_cache_executables_file!(skip_update: false)
        if DATABASE_FILE.exist? && !DATABASE_FILE.empty? &&
           (skip_update || (Time.now - Homebrew::EnvConfig.api_auto_update_secs.to_i) < DATABASE_FILE.mtime)
          return
        end

        url = "#{Homebrew::EnvConfig.api_domain}/#{ENDPOINT}"

        if ENV.fetch("CI", false)
          max_time = nil # allow more time in CI
          retries = Homebrew::EnvConfig.curl_retries.to_i
        else
          max_time = 10 # seconds
          retries = nil # do not retry by default
        end

        args = Utils::Curl.curl_args(max_time:, retries:)
        args += %W[
          --compressed
          --speed-limit #{ENV.fetch("HOMEBREW_CURL_SPEED_LIMIT")}
          --speed-time #{ENV.fetch("HOMEBREW_CURL_SPEED_TIME")}
        ]
        args.prepend("--time-cond", DATABASE_FILE.to_s) if DATABASE_FILE.exist? && !DATABASE_FILE.empty?

        Utils::Curl.curl_download(*args, url, to: DATABASE_FILE)
        FileUtils.touch(DATABASE_FILE, mtime: Time.now)

        Settings.write :commandnotfound, true
      end

      sig { params(cmd: String).returns(T::Array[String]) }
      def matches(cmd)
        DATABASE_FILE.readlines.select { |line| line.include?(cmd) }.map(&:chomp)
      end

      # Test if we have to reject the given formula, i.e. not suggest it.
      sig { params(name: String).returns(T::Boolean) }
      def reject_formula?(name)
        f = begin
          Formula[name]
        rescue
          nil
        end
        f.nil? || f.latest_version_installed? || f.requirements.any? { |r| r.required? && !r.satisfied? }
      end

      # Output explanation of how to get 'cmd' by installing one of the providing
      # formulae.
      sig { params(cmd: String, formulae: T::Array[String]).void }
      def explain_formulae_install(cmd, formulae)
        formulae.reject! { |f| reject_formula? f }

        return if formulae.blank?

        if formulae.size == 1
          puts <<~EOS
            The program '#{cmd}' is currently not installed. You can install it by typing:
              brew install #{formulae.first}
          EOS
        else
          puts <<~EOS
            The program '#{cmd}' can be found in the following formulae:
              * #{formulae * "\n  * "}
            Try: brew install <selected formula>
          EOS
        end
      end

      # if 'explain' is false, print all formulae that can be installed to get the
      # given command. If it's true, print them in human-readable form with an help
      # text.
      sig { params(cmd: String, explain: T::Boolean, skip_update: T::Boolean).void }
      def which_formula(cmd, explain: false, skip_update: false)
        download_and_cache_executables_file!(skip_update: skip_update)

        cmd = cmd.downcase

        formulae = (matches cmd).filter_map do |m|
          formula, cmds_text = m.split(":", 2)
          next if formula.nil? || cmds_text.nil?

          cmds = cmds_text.split
          formula if !cmds.nil? && cmds.include?(cmd)
        end

        return if formulae.blank?

        formulae.map! do |formula|
          formula.sub(/\(.*\)$/, "")
        end

        if explain
          explain_formulae_install(cmd, formulae)
        else
          puts formulae * "\n"
        end
      end
    end
  end
end
