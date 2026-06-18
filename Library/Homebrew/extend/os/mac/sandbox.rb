# typed: strict
# frozen_string_literal: true

require "erb"
require "fcntl"

module OS
  module Mac
    module Sandbox
      extend T::Helpers

      requires_ancestor { ::Sandbox }

      SANDBOX_EXEC = "/usr/bin/sandbox-exec"

      # This is defined in the macOS SDK but Ruby unfortunately does not expose it.
      # This value can be found by compiling a C program that prints TIOCSCTTY.
      TIOCSCTTY = 0x20007461

      SEATBELT_ERB = <<~ERB
        (version 1)
        (debug deny) ; log all denied operations to /var/log/system.log
        <%= rules.join("\n") %>
        (allow file-write*
            (literal "/dev/ptmx")
            (literal "/dev/dtracehelper")
            (literal "/dev/null")
            (literal "/dev/random")
            (literal "/dev/zero")
            (regex #"^/dev/fd/[0-9]+$")
            (regex #"^/dev/tty[a-z0-9]*$")
            )
        (deny file-write*) ; deny non-allowlist file write operations
        (deny file-write-setugid) ; deny non-allowlist file write SUID/SGID operations
        (deny file-write-mode) ; deny non-allowlist file write mode operations
        (allow process-exec
            (literal "/bin/ps")
            (with no-sandbox)
            ) ; allow certain processes running without sandbox
        (allow default) ; allow everything else
      ERB

      private_constant :SANDBOX_EXEC, :TIOCSCTTY, :SEATBELT_ERB

      sig { void }
      def allow_write_temp_and_cache
        allow_write_path "/private/tmp"
        allow_write_path "/private/var/tmp"
        allow_write path: "^/private/var/folders/[^/]+/[^/]+/[C,T]/", type: :regex
        super
      end

      # Xcode projects expect access to certain cache/archive dirs.
      sig { void }
      def allow_write_xcode
        home_write_paths.each { |path| allow_write_path path }
      end

      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::Sandbox) }

        sig { returns(T::Boolean) }
        def available?
          File.executable?(SANDBOX_EXEC)
        end

        sig { returns(Integer) }
        def terminal_ioctl_request
          TIOCSCTTY
        end
      end

      private

      sig { returns(T::Array[String]) }
      def home_write_paths
        home = Dir.home(ENV.fetch("USER"))
        ["#{home}/Library/Developer", "#{home}/Library/Caches/org.swift.swiftpm"]
      end

      sig { params(args: T::Array[T.any(String, ::Pathname)], tmpdir: String).returns(T::Array[T.any(String, ::Pathname)]) }
      def sandbox_command(args, tmpdir)
        seatbelt = File.new(File.join(tmpdir, "homebrew.sb"), "wx")
        seatbelt.write(seatbelt_profile)
        seatbelt.close

        [SANDBOX_EXEC, "-f", seatbelt.path, *args]
      end

      sig { returns(T::Boolean) }
      def allow_network_for_error_pipe?
        true
      end

      sig { void }
      def ensure_child_tty_available
        # We're opening and immediately closing so this is safe.
        # rubocop:disable Style/FileOpen
        File.open("/dev/tty", Fcntl::O_WRONLY).close # Workaround for https://developer.apple.com/forums/thread/663632
        # rubocop:enable Style/FileOpen
      end

      sig { void }
      def record_sandbox_log
        sleep 0.1 # wait for a bit to let syslog catch up the latest events.
        syslog_args = [
          "-F", "$((Time)(local)) $(Sender)[$(PID)]: $(Message)",
          "-k", "Time", "ge", T.must(start).to_i.to_s,
          "-k", "Message", "S", "deny",
          "-k", "Sender", "kernel",
          "-o",
          "-k", "Time", "ge", T.must(start).to_i.to_s,
          "-k", "Message", "S", "deny",
          "-k", "Sender", "sandboxd"
        ]
        logs = Utils.popen_read("syslog", *syslog_args)

        # These messages are confusing and non-fatal, so don't report them.
        logs = logs.lines.grep_v(/^.*Python\(\d+\) deny file-write.*pyc$/).join

        return if logs.empty?

        if (logfile_path = logfile)
          File.open(logfile_path, "w") do |log|
            log.write logs
            log.write "\nWe use time to filter sandbox log. Therefore, unrelated logs may be recorded.\n"
          end
        end

        return if !failed || !Homebrew::EnvConfig.verbose?

        ohai "Sandbox Log", logs
        $stdout.flush # without it, brew test-bot would fail to catch the log
      end

      sig { returns(String) }
      def seatbelt_profile
        ERB.new(SEATBELT_ERB).result_with_hash(rules: profile.rules.map { |rule| seatbelt_rule(rule) })
      end

      sig { params(rule: T.untyped).returns(String) }
      def seatbelt_rule(rule)
        s = +"("
        s << (rule.allow ? "allow" : "deny")
        s << " #{rule.operation}"
        s << " (#{seatbelt_path_filter(rule.filter)})" if rule.filter
        s << " (with #{rule.modifier})" if rule.modifier
        s << ")"
        s.freeze
      end

      sig { params(filter: T.untyped).returns(String) }
      def seatbelt_path_filter(filter)
        case filter.type
        when :regex   then "regex #\"#{filter.path}\""
        when :subpath then "subpath \"#{seatbelt_quote(filter.path)}\""
        when :literal then "literal \"#{seatbelt_quote(filter.path)}\""
        else raise ArgumentError, "Invalid path filter type: #{filter.type}"
        end
      end

      # `"` and `\` are the only characters special inside a double-quoted
      # seatbelt string, so escaping just those two lets any path (spaces,
      # parentheses, quotes, backslashes, even newlines) be expressed safely.
      sig { params(path: String).returns(String) }
      def seatbelt_quote(path)
        path.gsub(/["\\]/) { |char| "\\#{char}" }
      end
    end
  end
end

Sandbox.prepend(OS::Mac::Sandbox)
Sandbox.singleton_class.prepend(OS::Mac::Sandbox::ClassMethods)
