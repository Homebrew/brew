# typed: strict
# frozen_string_literal: true

require "erb"
require "fcntl"
require "fiddle"

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
        (deny network-outbound (to unix-socket))
        <% if network_access_allowed %>
        (allow network-outbound (to unix-socket (path-literal "/private/var/run/mDNSResponder")))
        <% end %>
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
        (deny mach-lookup)
        (allow mach-lookup
            (xpc-service-name "com.apple.MTLCompilerService")
            (global-name "com.apple.mobileassetd.v2")
            (global-name "com.apple.sysmond")
            (global-name "com.apple.lsd.mapdb")
            (global-name "com.apple.bsd.dirhelper")
            (global-name "com.apple.system.opendirectoryd.libinfo")
            (global-name "com.apple.system.opendirectoryd.membership")
            (global-name "com.apple.PowerManagement.control")
            (global-name "com.apple.SecurityServer")
            (global-name "com.apple.networkd")
            (global-name "com.apple.ocspd")
            (global-name "com.apple.trustd.agent")
            (global-name "com.apple.SystemConfiguration.DNSConfiguration")
            (global-name "com.apple.SystemConfiguration.configd")
            (global-name "com.apple.FSEvents")
            )
        (deny lsopen)
        (deny appleevent-send)
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
        allow_write path: "^/private/var/folders/[^/]+/[^/]+/T/xcrun_db(-[^/]+)?$", type: :regex
      end

      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::Sandbox) }

        sig { returns(T::Boolean) }
        def available?
          File.executable?(SANDBOX_EXEC)
        end

        # Nested `sandbox-exec` invocations hang inside an existing macOS sandbox
        # (e.g. an agent's), so detect that via the libSystem `sandbox_check`
        # syscall. The shared `avoid_nested_sandboxing?` only calls this once the
        # `$HOMEBREW_AVOID_NESTED_SANDBOXING` opt-in is set.
        sig { returns(T::Boolean) }
        def nested_sandbox?
          sandbox_check = Fiddle::Function.new(
            Fiddle.dlopen(nil)["sandbox_check"],
            [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT,
          )
          sandbox_check.call(Process.pid, nil, 0) == 1
        rescue Fiddle::DLError
          false
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

      sig { params(args: T::Array[T.any(String, ::Pathname)], _tmpdir: String).returns(T::Array[T.any(String, ::Pathname)]) }
      def sandbox_command(args, _tmpdir)
        [SANDBOX_EXEC, "-p", seatbelt_profile, *args]
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
        start_time = start
        raise "Cannot record the sandbox log before the sandbox has started" if start_time.nil?

        sleep 0.1 # wait for a bit to let syslog catch up the latest events.
        since = start_time.to_i.to_s
        syslog_args = [
          "-F", "$((Time)(local)) $(Sender)[$(PID)]: $(Message)",
          "-k", "Time", "ge", since,
          "-k", "Message", "S", "deny",
          "-k", "Sender", "kernel",
          "-o",
          "-k", "Time", "ge", since,
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
        ERB.new(SEATBELT_ERB).result_with_hash(
          rules:                  profile.rules.map { |rule| seatbelt_rule(rule) },
          network_access_allowed: profile.rules.none? do |rule|
            !rule.allow && rule.operation == "network*" && rule.filter.nil?
          end,
        )
      end

      sig { params(rule: T.untyped).returns(String) }
      def seatbelt_rule(rule)
        s = +"("
        s << (rule.allow ? "allow" : "deny")
        s << " #{rule.operation}"
        s << " network-outbound" if rule.allow && rule.operation == "network*"
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
