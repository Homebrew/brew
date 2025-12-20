# typed: strict
# frozen_string_literal: true

module Utils
  module Output
    module Mixin
      extend T::Helpers

      requires_ancestor { Kernel }

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
      sig { params(message: T.any(String, Exception)).void }
      def opoo(message)
        require "utils/github/actions"
        return if GitHub::Actions.puts_annotation_if_env_set!(:warning, message.to_s)

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

      # Print an error message and fail immediately.
      #
      # @api public
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

      sig { params(string: String).returns(String) }
      def pretty_outdated(string)
        if !$stdout.tty?
          string
        elsif Homebrew::EnvConfig.no_emoji?
          Formatter.error("#{Tty.bold}#{string} (outdated)#{Tty.reset}")
        else
          "#{Tty.bold}#{string} #{Formatter.warning("⚠")}#{Tty.reset}"
        end
      end

      sig { params(string: String).returns(String) }
      def pretty_uninstalled(string)
        if !$stdout.tty?
          string
        elsif Homebrew::EnvConfig.no_emoji?
          Formatter.error("#{Tty.bold}#{string} (uninstalled)#{Tty.reset}")
        else
          "#{Tty.bold}#{string} #{Formatter.error("✘")}#{Tty.reset}"
        end
      end

      sig { params(seconds: T.nilable(T.any(Integer, Float))).returns(String) }
      def pretty_duration(seconds)
        seconds = seconds.to_i
        res = +""

        if seconds > 59
          minutes = seconds / 60
          seconds %= 60
          res = +Utils.pluralize("minute", minutes, include_count: true)
          return res.freeze if seconds.zero?

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
