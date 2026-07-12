# typed: strict
# frozen_string_literal: true

module Utils
  # Helper methods for outputting messages in Homebrew's formats.
  module Output
    # Mixin used to add these helpers to stdout and stderr.
    module Mixin
      extend T::Helpers

      requires_ancestor { Kernel }

      # Keep in sync with `ohai` in Library/Homebrew/utils.sh.
      sig { params(title: String).returns(String) }
      def ohai_title(title)
        verbose = if respond_to?(:verbose?)
          T.unsafe(self).verbose?
        else
          Context.current.verbose?
        end

        title = Tty.truncate(title.to_s) if $stdout.tty? && !verbose
        Formatter.headline(title, color: :blue)
      end

      sig { params(title: T.any(String, Exception), sput: T.anything).void }
      def ohai(title, *sput)
        puts ohai_title(title.to_s)
        puts sput
      end

      sig { params(title: T.any(String, Exception), sput: T.anything, always_display: T::Boolean).void }
      def odebug(title, *sput, always_display: false)
        debug = if respond_to?(:debug)
          T.unsafe(self).debug?
        else
          Context.current.debug?
        end

        return if !debug && !always_display

        $stderr.puts Formatter.headline(title.to_s, color: :magenta)
        $stderr.puts sput unless sput.empty?
      end

      sig { params(title: String, truncate: T.any(Symbol, T::Boolean)).returns(String) }
      def oh1_title(title, truncate: :auto)
        verbose = if respond_to?(:verbose?)
          T.unsafe(self).verbose?
        else
          Context.current.verbose?
        end

        title = Tty.truncate(title.to_s) if $stdout.tty? && !verbose && truncate == :auto
        Formatter.headline(title, color: :green)
      end

      sig { params(title: String, truncate: T.any(Symbol, T::Boolean)).void }
      def oh1(title, truncate: :auto)
        puts oh1_title(title, truncate:)
      end

      # Print a warning message.
      #
      # @api public
      # Keep in sync with `opoo` in Library/Homebrew/utils.sh.
      sig { params(message: T.any(String, Exception)).void }
      def opoo(message)
        require "utils/github/actions"
        return if GitHub::Actions.puts_annotation_if_env_set!(:warning, message.to_s)

        require "utils/formatter"

        Tty.with($stderr) do |stderr|
          stderr.puts Formatter.warning(message, label: "Warning")
        end
      end

      sig { params(message: T.any(String, Exception)).void }
      def opoo_without_github_actions_annotation(message)
        require "utils/github/actions"
        return opoo(message) unless GitHub::Actions.env_set?

        require "utils/formatter"

        Tty.with($stderr) do |stderr|
          stderr.puts Formatter.warning(message, label: "Warning")
        end
      end

      # Print a warning message only if not running in GitHub Actions.
      #
      # @api public
      sig { params(message: T.any(String, Exception)).void }
      def opoo_outside_github_actions(message)
        require "utils/github/actions"
        return if GitHub::Actions.env_set?

        opoo(message)
      end

      # Print an error message.
      #
      # @api public
      # Keep in sync with `onoe` in Library/Homebrew/utils.sh.
      sig { params(message: T.any(String, Exception)).void }
      def onoe(message)
        require "utils/github/actions"
        return if GitHub::Actions.puts_annotation_if_env_set!(:error, message.to_s)

        require "utils/formatter"

        Tty.with($stderr) do |stderr|
          stderr.puts Formatter.error(message, label: "Error")
        end
      end

      # Print an error message and fail at the end of the program.
      #
      # @api public
      sig { params(error: T.any(String, Exception)).void }
      def ofail(error)
        onoe error
        Homebrew.failed = true
      end

      sig { params(issues_url: String, homebrew: T::Boolean, read_this: T::Boolean).returns(String) }
      def issue_reporting_message(issues_url, homebrew: false, read_this: false)
        formatted_issues_url = Formatter.url(issues_url)

        if read_this
          Formatter.error(formatted_issues_url, label: "READ THIS")
        elsif homebrew
          <<~EOS
            #{Tty.bold}Please report this issue:#{Tty.reset}
              #{formatted_issues_url}
          EOS
        else
          <<~EOS
            If reporting this issue please do so at (not Homebrew/* repositories):
              #{formatted_issues_url}
          EOS
        end
      end

      # Print an error message and fail immediately.
      #
      # @api public
      # Keep in sync with `odie` in Library/Homebrew/utils.sh.
      sig { params(error: T.any(String, Exception)).returns(T.noreturn) }
      def odie(error)
        onoe error
        exit 1
      end

      # Output a deprecation warning/error message.
      sig {
        params(method: String, replacement: T.nilable(T.any(String, Symbol)), disable: T::Boolean,
               disable_on: T.nilable(Time), disable_for_developers: T::Boolean, caller: T::Array[String]).void
      }
      def odeprecated(method, replacement = nil,
                      disable:                false,
                      disable_on:             nil,
                      disable_for_developers: true,
                      caller:                 send(:caller))
        replacement_message = if replacement
          "Use #{replacement} instead."
        else
          "There is no replacement."
        end

        unless disable_on.nil?
          if disable_on > Time.now
            will_be_disabled_message = " and will be disabled on #{disable_on.strftime("%Y-%m-%d")}"
          else
            disable = true
          end
        end

        verb = if disable
          "disabled"
        else
          "deprecated#{will_be_disabled_message}"
        end

        # Try to show the most relevant location in message, i.e. (if applicable):
        # - Location in a formula.
        # - Location of caller of deprecated method (if all else fails).
        backtrace = caller

        # Don't throw deprecations at all for cached, .brew or .metadata files.
        return if backtrace.any? do |line|
          next true if line.include?(HOMEBREW_CACHE.to_s)
          next true if line.include?("/.brew/")
          next true if line.include?("/.metadata/")

          next false unless line.match?(HOMEBREW_TAP_PATH_REGEX)

          path = Pathname(line.split(":", 2).first)
          next false unless path.file?
          next false unless path.readable?

          formula_contents = path.read
          formula_contents.include?(" deprecate! ") || formula_contents.include?(" disable! ")
        end

        tap_message = T.let(nil, T.nilable(String))

        backtrace.each do |line|
          next unless (match = line.match(HOMEBREW_TAP_PATH_REGEX))

          require "tap"

          tap = Tap.fetch(match[:user], match[:repository])
          tap_message = "\nPlease report this issue to the #{tap.full_name} tap"
          tap_message += " (not Homebrew/* repositories)" unless tap.official?
          tap_message += ", or even better, submit a PR to fix it" if replacement
          tap_message << ":\n  #{line.sub(/^(.*:\d+):.*$/, '\1')}\n\n"
          break
        end
        file, line, = backtrace.first.split(":")
        line = line.to_i if line.present?

        message = "Calling #{method} is #{verb}! #{replacement_message}"
        message << tap_message if tap_message
        message.freeze

        disable = true if disable_for_developers && Homebrew::EnvConfig.developer?
        if disable || Homebrew.raise_deprecation_exceptions?
          require "utils/github/actions"
          GitHub::Actions.puts_annotation_if_env_set!(:error, message, file:, line:)
          exception = MethodDeprecatedError.new(message)
          exception.set_backtrace(backtrace)
          raise exception
        elsif !Homebrew.auditing?
          opoo message
        end
      end

      sig {
        params(method: String, replacement: T.nilable(T.any(String, Symbol)),
               disable_on: T.nilable(Time), disable_for_developers: T::Boolean, caller: T::Array[String]).void
      }
      def odisabled(method, replacement = nil,
                    disable_on:             nil,
                    disable_for_developers: true,
                    caller:                 send(:caller))
        # This odeprecated should stick around indefinitely.
        odeprecated(method, replacement, disable: true, disable_on:, disable_for_developers:, caller:)
      end

      # Keep status labels, colours and emoji in sync with
      # `pretty_installed` in Library/Homebrew/utils.sh.
      sig { params(string: String).returns(String) }
      def pretty_installed(string)
        if !$stdout.tty?
          string
        elsif Homebrew::EnvConfig.no_emoji?
          Formatter.success("#{Tty.bold}#{string} (installed)#{Tty.reset}")
        else
          "#{Tty.bold}#{string} #{Formatter.success("✔")}#{Tty.reset}"
        end
      end

      sig { params(string: String, bold: T::Boolean).returns(String) }
      def pretty_upgradable(string, bold: true)
        weight = bold ? Tty.bold.to_s : ""
        if !$stdout.tty?
          string
        elsif Homebrew::EnvConfig.no_emoji?
          "#{weight}#{string} (upgradable)#{Tty.reset}"
        else
          "#{weight}#{string} #{Formatter.success("↑")}#{Tty.reset}"
        end
      end

      sig { params(string: String).returns(String) }
      def pretty_deprecated(string)
        if $stdout.tty?
          "#{string} #{Formatter.warning("(deprecated)")}"
        else
          string
        end
      end

      sig { params(string: String).returns(String) }
      def pretty_disabled(string)
        if $stdout.tty?
          "#{string} #{Formatter.error("(disabled)")}"
        else
          string
        end
      end

      # Keep status labels, colours and emoji in sync with
      # `pretty_uninstalled` in Library/Homebrew/utils.sh.
      sig { params(string: String, bold: T::Boolean).returns(String) }
      def pretty_uninstalled(string, bold: true)
        weight = bold ? Tty.bold.to_s : ""
        if !$stdout.tty?
          string
        elsif Homebrew::EnvConfig.no_emoji?
          Formatter.error("#{weight}#{string} (uninstalled)#{Tty.reset}")
        else
          "#{weight}#{string} #{Formatter.error("✘")}#{Tty.reset}"
        end
      end

      sig { params(string: String, bold: T::Boolean).returns(String) }
      def pretty_unmarked(string, bold: true)
        if bold && $stdout.tty?
          "#{Tty.bold}#{string}#{Tty.reset}"
        else
          string
        end
      end

      sig { params(string: String, bold: T::Boolean).returns(String) }
      def pretty_warning(string, bold: true)
        weight = bold ? Tty.bold.to_s : ""
        if !$stdout.tty?
          string
        elsif Homebrew::EnvConfig.no_emoji?
          Formatter.warning("#{weight}#{string} (warning)#{Tty.reset}")
        else
          "#{weight}#{string} #{Formatter.warning("⚠")}#{Tty.reset}"
        end
      end

      sig {
        params(string: String, installed: T::Boolean, warning: T::Boolean, outdated: T::Boolean,
               deprecated: T::Boolean, disabled: T::Boolean, mark_uninstalled: T::Boolean,
               bold: T.nilable(T::Boolean)).returns(String)
      }
      def pretty_install_status(string, installed:, warning: false, outdated: false, deprecated: false,
                                disabled: false, mark_uninstalled: true, bold: nil)
        bold = installed if bold.nil?
        status = if warning
          pretty_warning(string, bold:)
        elsif installed && outdated
          pretty_upgradable(string, bold:)
        elsif installed
          pretty_installed(string)
        elsif mark_uninstalled
          pretty_uninstalled(string, bold:)
        else
          pretty_unmarked(string, bold:)
        end
        if disabled
          pretty_disabled(status)
        elsif deprecated
          pretty_deprecated(status)
        else
          status
        end
      end

      sig { params(seconds: T.nilable(T.any(Integer, Float))).returns(String) }
      def pretty_duration(seconds)
        seconds = seconds.to_i
        hide_seconds = seconds > 300

        minutes, seconds = seconds.divmod(60)
        hours, minutes = minutes.divmod(60)

        res = +""

        if hours.positive?
          res << Utils.pluralize("hour", hours, include_count: true)
          return res.freeze if minutes.zero?

          res << " " << Utils.pluralize("minute", minutes, include_count: true)
          return res.freeze
        end

        if minutes.positive?
          res << Utils.pluralize("minute", minutes, include_count: true)
          return res.freeze if hide_seconds || seconds.zero?

          res << " "
        end

        res << Utils.pluralize("second", seconds, include_count: true)
        res.freeze
      end
    end

    extend Mixin
    $stdout.extend Mixin
    $stderr.extend Mixin
  end
end
