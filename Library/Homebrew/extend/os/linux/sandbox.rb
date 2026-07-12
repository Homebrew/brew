# typed: strict
# frozen_string_literal: true

require "fileutils"
require "env_config"
require "system_command"
require "utils/popen"
require "utils/github/actions"

module OS
  module Linux
    module Sandbox
      extend T::Helpers

      requires_ancestor { ::Sandbox }

      BUBBLEWRAP = "bwrap"
      BUBBLEWRAP_TEST_ARGS = [
        "--unshare-user",
        "--unshare-ipc",
        "--unshare-pid",
        "--unshare-uts",
        "--unshare-cgroup-try",
        "--ro-bind", "/", "/",
        "--proc", "/proc",
        "--dev", "/dev",
        "true"
      ].freeze
      SYSTEM_BUBBLEWRAP_PATHS = %w[
        /usr/bin
        /bin
      ].freeze
      HOMEBREW_BUBBLEWRAP_PATHS = [
        "#{HOMEBREW_PREFIX}/bin",
      ].freeze
      NESTED_BUBBLEWRAP_ERROR = "Creating new namespace failed: nesting depth or /proc/sys/user/max_*_namespaces " \
                                "exceeded"
      class SysctlSetting < T::Struct
        const :assignment, String
        const :description, T::Array[String]
        const :optional, T::Boolean, default: false
      end
      # These settings mirror the `sysctl` assignments in
      # Library/Homebrew/cmd/setup-sandbox.sh; keep both in sync.
      SANDBOX_SYSCTL_SETTINGS = T.let([
        SysctlSetting.new(
          assignment:  "kernel.unprivileged_userns_clone=1",
          description: [
            "Allows unprivileged processes to create user namespaces. Rootless",
            "Bubblewrap needs this to isolate builds without elevated privileges.",
          ],
        ),
        SysctlSetting.new(
          assignment:  "user.max_user_namespaces=28633",
          description: [
            "Allows each user to allocate enough user namespaces. A zero or low",
            "limit can prevent Bubblewrap from creating its sandbox.",
          ],
        ),
        SysctlSetting.new(
          assignment:  "kernel.apparmor_restrict_unprivileged_userns=0",
          description: [
            "Allows unprivileged user namespaces on AppArmor-enabled systems",
            "that restrict them by default. Older kernels may not provide this",
            "setting.",
          ],
          optional:    true,
        ),
      ].freeze, T::Array[SysctlSetting])
      # `TIOCSCTTY` from `<asm-generic/ioctls.h>`; Ruby does not expose it.
      TIOCSCTTY = 0x540E
      # Per-distro Bubblewrap install commands, detected by package manager and
      # checked in priority order. Mirrors the build tools instructions in
      # `Homebrew/install`'s `install.sh`.
      BUBBLEWRAP_INSTALL_COMMANDS = T.let({
        "apt-get" => "sudo apt-get install bubblewrap",
        "dnf"     => "sudo dnf install bubblewrap",
        "yum"     => "sudo yum install bubblewrap",
        "pacman"  => "sudo pacman -S bubblewrap",
        "apk"     => "sudo apk add bubblewrap",
      }.freeze, T::Hash[String, String])
      private_constant :BUBBLEWRAP, :BUBBLEWRAP_TEST_ARGS, :SYSTEM_BUBBLEWRAP_PATHS, :HOMEBREW_BUBBLEWRAP_PATHS,
                       :NESTED_BUBBLEWRAP_ERROR, :SysctlSetting, :SANDBOX_SYSCTL_SETTINGS, :TIOCSCTTY,
                       :BUBBLEWRAP_INSTALL_COMMANDS

      sig { returns(::PATH) }
      def self.bubblewrap_candidate_paths
        ::Sandbox.executable_candidate_paths
      end

      sig { returns(T.nilable(::Pathname)) }
      def self.bubblewrap_executable
        ::Sandbox.executable
      end

      sig { returns(::Pathname) }
      def self.bubblewrap_executable!
        bubblewrap_executable || raise("Bubblewrap is required to use the Linux sandbox.")
      end

      sig { void }
      def allow_write_temp_and_cache
        allow_write_path "/tmp"
        allow_write_path "/var/tmp"
        allow_write_path HOMEBREW_TEMP
        allow_write_path HOMEBREW_CACHE
      end

      sig { void }
      def allow_cvs
        cvspass = ::Pathname.new("#{Dir.home(ENV.fetch("USER"))}/.cvspass")
        allow_write path: cvspass, type: :literal if cvspass.exist?
      end

      sig { void }
      def allow_fossil
        [".fossil", ".fossil-journal"].each do |file|
          fossil_file = ::Pathname.new("#{Dir.home(ENV.fetch("USER"))}/#{file}")
          allow_write path: fossil_file, type: :literal if fossil_file.exist?
        end
      end

      module ClassMethods
        extend T::Helpers
        include SystemCommand::Mixin
        include Utils::Output::Mixin

        requires_ancestor { T.class_of(::Sandbox) }

        sig { returns(String) }
        def executable_name
          BUBBLEWRAP
        end

        sig { params(candidate: ::Pathname).returns(T::Boolean) }
        def executable_usable?(candidate)
          !File.stat(candidate).setuid?
        end

        sig { returns(T::Array[String]) }
        def system_bubblewrap_paths
          SYSTEM_BUBBLEWRAP_PATHS
        end

        sig { returns(::PATH) }
        def executable_candidate_paths
          PATH.new(HOMEBREW_BUBBLEWRAP_PATHS, system_bubblewrap_paths, super)
        end

        sig { returns(::PATH) }
        def bubblewrap_candidate_paths
          executable_candidate_paths
        end

        sig { returns(T.nilable(::Pathname)) }
        def bubblewrap_executable
          executable
        end

        sig { returns(::Pathname) }
        def bubblewrap_executable!
          bubblewrap_executable || raise("Bubblewrap is required to use the Linux sandbox.")
        end

        sig { params(install_from_tests: T::Boolean).void }
        def ensure_sandbox_installed!(install_from_tests: false)
          return unless Homebrew::EnvConfig.sandbox_linux?
          return if ENV["HOMEBREW_TESTS"] && !install_from_tests
          return if ENV["HOMEBREW_INSTALLING_BUBBLEWRAP"]
          return if bubblewrap_executable

          begin
            require "exceptions"
            require "formula"
            with_env(HOMEBREW_INSTALLING_BUBBLEWRAP: "1") do
              ::Formula["bubblewrap"].ensure_installed!(reason: "Linux sandboxing")
            end
            reset_state!
            return if bubblewrap_executable
          rescue ::FormulaUnavailableError
            nil
          end

          return unless GitHub::Actions.env_set?
          return unless ENV.fetch("HOMEBREW_GITHUB_HOSTED_RUNNER", nil)
          return unless which("apt-get")

          ohai "Installing Bubblewrap..."
          command = ["apt-get", "install", "--yes", "bubblewrap"]
          command.unshift("sudo") unless Process.euid.zero?
          system(*command)
          reset_state!
        end

        sig { returns(T::Boolean) }
        def available?
          state == :available
        end

        # Bubblewrap reports this specific namespace error when an outer
        # Bubblewrap sandbox prevents Homebrew from creating another rootless
        # sandbox. The shared `avoid_nested_sandboxing?` only calls this once the
        # `$HOMEBREW_AVOID_NESTED_SANDBOXING` opt-in is set.
        sig { returns(T::Boolean) }
        def nested_sandbox?
          return false unless Homebrew::EnvConfig.sandbox_linux?

          bubblewrap = bubblewrap_executable
          return false unless bubblewrap

          Utils.popen_read(bubblewrap.to_s, *BUBBLEWRAP_TEST_ARGS, err: :out).include?(NESTED_BUBBLEWRAP_ERROR)
        end

        sig { returns(Symbol) }
        def state
          return :disabled unless Homebrew::EnvConfig.sandbox_linux?

          @state ||= T.let(compute_state, T.nilable(Symbol))
        end

        sig { void }
        def reset_state!
          @state = T.let(nil, T.nilable(Symbol))
        end

        sig { returns(T::Array[String]) }
        def configuration_commands
          SANDBOX_SYSCTL_SETTINGS.map do |setting|
            command = "sudo sysctl -w #{setting.assignment}"
            command += " || true" if setting.optional
            command
          end
        end

        sig { returns(T::Array[String]) }
        def configuration_command_messages
          commands = configuration_commands
          SANDBOX_SYSCTL_SETTINGS.each_with_index.flat_map do |setting, index|
            [
              "  #{commands.fetch(index)}",
              *setting.description.map { |line| "    #{line}" },
            ]
          end
        end

        sig { void }
        def configure!
          unless bubblewrap_executable
            ensure_sandbox_installed!(install_from_tests: true)
            unless bubblewrap_executable
              reset_state!
              return
            end
          end

          ohai "Configuring Bubblewrap..."
          command = [HOMEBREW_BREW_FILE.to_s, "setup-sandbox"]
          command.unshift("sudo") unless Process.euid.zero?
          raise ErrorDuringExecution.new(command, status: $CHILD_STATUS || 1) unless system(*command)

          reset_state!
        end

        sig { returns(T.nilable(String)) }
        def failure_reason
          case state
          when :disabled, :available
            nil
          when :missing
            "Bubblewrap is required to use the Linux sandbox but was not found."
          when :setuid
            "A rootless Bubblewrap executable is required to use the Linux sandbox, " \
            "but all found `bwrap` executables are setuid."
          when :unavailable
            "Bubblewrap is installed but cannot create a rootless sandbox."
          else
            "The Linux sandbox is not available."
          end
        end

        sig { returns(T.nilable(String)) }
        def sandbox_install_command
          BUBBLEWRAP_INSTALL_COMMANDS.find { |package_manager, _| which(package_manager) }&.last
        end

        # `ioctl` request used to attach the sandboxed child to a controlling TTY.
        sig { returns(Integer) }
        def terminal_ioctl_request
          TIOCSCTTY
        end

        private

        sig { returns(Symbol) }
        def compute_state
          bubblewraps = bubblewrap_executables
          return :missing if bubblewraps.empty?

          bubblewraps = bubblewraps.select { |candidate| executable_usable?(candidate) }
          return :setuid if bubblewraps.empty?

          return :available if bubblewraps.any? { |candidate| bubblewrap_sandbox_available?(candidate) }

          :unavailable
        end

        sig { returns(T::Array[::Pathname]) }
        def bubblewrap_executables
          executable_candidate_paths.filter_map do |path|
            begin
              candidate = ::Pathname.new(File.expand_path(executable_name, path))
            rescue ArgumentError
              next
            end

            candidate if candidate.file? && candidate.executable?
          end
        end

        sig { params(bubblewrap: ::Pathname).returns(T::Boolean) }
        def bubblewrap_sandbox_available?(bubblewrap)
          result = system_command(
            bubblewrap,
            args:         BUBBLEWRAP_TEST_ARGS,
            print_stderr: false,
          )
          return true if result.success?

          opoo "bubblewrap test probe failed"
          $stderr.print result.merged_output
          false
        end
      end

      sig { params(args: T.any(String, ::Pathname)).void }
      def run(*args)
        @prepared_writable_paths = T.let([], T.nilable(T::Array[::Pathname]))
        @masked_read_paths = T.let([], T.nilable(T::Array[::Pathname]))
        old_report_on_exception = T.let(Thread.report_on_exception, T.nilable(T::Boolean))
        Thread.report_on_exception = false
        super
      ensure
        Thread.report_on_exception = old_report_on_exception unless old_report_on_exception.nil?
        @prepared_writable_paths&.reverse_each do |path|
          path.rmdir if path.directory?
        rescue Errno::ENOENT, Errno::ENOTEMPTY
          nil
        end
        @prepared_writable_paths = nil
        @masked_read_paths&.reverse_each { |path| FileUtils.rm_rf(path) }
        @masked_read_paths = nil
      end

      private

      sig { params(args: T::Array[T.any(String, ::Pathname)], tmpdir: String).returns(T::Array[T.any(String, ::Pathname)]) }
      def sandbox_command(args, tmpdir)
        [::Sandbox.executable!, *bubblewrap_args(tmpdir), "--", *args]
      end

      sig { params(tmpdir: String).returns(T::Array[String]) }
      def bubblewrap_args(tmpdir)
        args = T.let([
          "--unshare-user",
          "--unshare-ipc",
          "--unshare-pid",
          "--unshare-uts",
          "--unshare-cgroup-try",
          "--die-with-parent",
          "--new-session",
          "--ro-bind", "/", "/",
          "--dev", "/dev",
          "--proc", "/proc"
        ], T::Array[String])
        args << "--unshare-net" if deny_all_network?

        writable_paths.each do |path, type|
          prepare_writable_path(path, type)
          args += ["--bind", path, path]
        end

        denied_write_paths.each do |path|
          next unless File.exist?(path)

          args += ["--ro-bind", path, path]
        end

        denied_read_paths.each do |path|
          next unless File.exist?(path)

          args += if File.directory?(path)
            ["--bind", masked_read_path, path]
          else
            ["--ro-bind", File::NULL, path]
          end
        end

        args += ["--bind", tmpdir, tmpdir, "--chdir", tmpdir]

        args
      end

      sig { returns(T::Boolean) }
      def deny_all_network?
        profile.rules.any? do |rule|
          !rule.allow && rule.operation == "network*" && rule.filter.nil?
        end
      end

      sig { returns(T::Hash[String, Symbol]) }
      def writable_paths
        profile.rules.each_with_object({}) do |rule, paths|
          next if !rule.allow || !rule.operation.start_with?("file-write")
          next unless (filter = rule.filter)

          case filter.type
          when :literal, :subpath
            paths[filter.path] ||= filter.type
          when :regex
            raise ArgumentError, "Linux sandbox does not support regex path filters: #{filter.path}"
          else
            raise ArgumentError, "Invalid path filter type: #{filter.type}"
          end
        end
      end

      sig { returns(T::Array[String]) }
      def denied_write_paths
        profile.rules.filter_map do |rule|
          next if rule.allow || !rule.operation.start_with?("file-write")

          filter = rule.filter
          filter.path if filter && [:literal, :subpath].include?(filter.type)
        end.uniq
      end

      sig { returns(T::Array[String]) }
      def denied_read_paths
        profile.rules.filter_map do |rule|
          next if rule.allow || !rule.operation.start_with?("file-read")

          filter = rule.filter
          filter.path if filter && [:literal, :subpath].include?(filter.type)
        end.uniq
      end

      sig { returns(String) }
      def masked_read_path
        path = ::Pathname.new(Dir.mktmpdir("homebrew-sandbox-deny-read", HOMEBREW_TEMP))
        @masked_read_paths&.<< path
        path.to_s
      end

      sig { params(path: String, type: Symbol).void }
      def prepare_writable_path(path, type)
        pathname = ::Pathname.new(path)
        return if pathname.exist?

        if type == :literal
          FileUtils.mkdir_p(pathname.dirname)
          FileUtils.touch(pathname)
        else
          FileUtils.mkdir_p(pathname)
          @prepared_writable_paths&.<< pathname
        end
      end
    end
  end
end

Sandbox.prepend(OS::Linux::Sandbox)
Sandbox.singleton_class.prepend(OS::Linux::Sandbox::ClassMethods)
