# typed: strict
# frozen_string_literal: true

require "fileutils"
require "env_config"
require "utils/output"
require "extend/os/linux/sandbox/backend"

class Sandbox
  class Landlock < LinuxBackend
    include Utils::Output::Mixin

    # Keep these constants and structure layouts in sync with Linux's Landlock UAPI:
    # https://github.com/torvalds/linux/blob/master/include/uapi/linux/landlock.h
    CREATE_RULESET_VERSION = 1
    RULE_PATH_BENEATH = 1

    # Linux's `prctl(2)` operation and `open(2)` flags come from these UAPI headers:
    # https://github.com/torvalds/linux/blob/master/include/uapi/linux/prctl.h
    # https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/fcntl.h
    PR_SET_NO_NEW_PRIVS = 38
    O_PATH = 010000000
    O_CLOEXEC = 02000000

    # Landlock has no dedicated libc wrappers, so call `syscall(2)` as documented:
    # https://man7.org/linux/man-pages/man2/landlock_create_ruleset.2.html
    # Homebrew's x86_64 and arm64 Linux architectures both use these numbers:
    # https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl
    # https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/unistd.h
    CREATE_RULESET_SYSCALL = 444
    ADD_RULE_SYSCALL = 445
    RESTRICT_SELF_SYSCALL = 446

    ACCESS_FS_EXECUTE = 0x0001
    ACCESS_FS_WRITE_FILE = 0x0002
    ACCESS_FS_READ_FILE = 0x0004
    ACCESS_FS_READ_DIR = 0x0008
    ACCESS_FS_REMOVE_DIR = 0x0010
    ACCESS_FS_REMOVE_FILE = 0x0020
    ACCESS_FS_MAKE_CHAR = 0x0040
    ACCESS_FS_MAKE_DIR = 0x0080
    ACCESS_FS_MAKE_REG = 0x0100
    ACCESS_FS_MAKE_SOCK = 0x0200
    ACCESS_FS_MAKE_FIFO = 0x0400
    ACCESS_FS_MAKE_BLOCK = 0x0800
    ACCESS_FS_MAKE_SYM = 0x1000
    ACCESS_FS_REFER = 0x2000
    ACCESS_FS_TRUNCATE = 0x4000
    ACCESS_FS_IOCTL_DEV = 0x8000
    ACCESS_FS_RESOLVE_UNIX = 0x10000

    ACCESS_NET_BIND_TCP = 0x01
    ACCESS_NET_CONNECT_TCP = 0x02
    ACCESS_NET_BIND_UDP = 0x04
    ACCESS_NET_CONNECT_SEND_UDP = 0x08
    SCOPE_ABSTRACT_UNIX_SOCKET = 0x01
    # ABI 3 is the first version that can restrict both cross-directory
    # renames and truncation:
    # https://www.kernel.org/doc/html/latest/userspace-api/landlock.html#previous-limitations
    MINIMUM_ABI = 3
    # UDP controls required to block all network access were added in ABI 10:
    # https://www.kernel.org/doc/html/latest/userspace-api/landlock.html#network-flags
    MINIMUM_FULL_NETWORK_ABI = 10

    WRITE_ACCESS_FS = T.let(
      (ACCESS_FS_WRITE_FILE | ACCESS_FS_REMOVE_DIR | ACCESS_FS_REMOVE_FILE | ACCESS_FS_MAKE_CHAR |
      ACCESS_FS_MAKE_DIR | ACCESS_FS_MAKE_REG | ACCESS_FS_MAKE_SOCK | ACCESS_FS_MAKE_FIFO |
      ACCESS_FS_MAKE_BLOCK | ACCESS_FS_MAKE_SYM).freeze,
      Integer,
    )
    FILE_WRITE_ACCESS_FS = T.let((ACCESS_FS_WRITE_FILE | ACCESS_FS_TRUNCATE).freeze, Integer)
    FILE_READ_ACCESS_FS = T.let((ACCESS_FS_EXECUTE | ACCESS_FS_READ_FILE).freeze, Integer)
    READ_ACCESS_FS = T.let((ACCESS_FS_EXECUTE | ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR).freeze, Integer)
    private_constant :CREATE_RULESET_VERSION, :RULE_PATH_BENEATH, :PR_SET_NO_NEW_PRIVS, :O_PATH, :O_CLOEXEC,
                     :CREATE_RULESET_SYSCALL, :ADD_RULE_SYSCALL, :RESTRICT_SELF_SYSCALL,
                     :ACCESS_FS_EXECUTE, :ACCESS_FS_WRITE_FILE, :ACCESS_FS_READ_FILE, :ACCESS_FS_READ_DIR,
                     :ACCESS_FS_REMOVE_DIR, :ACCESS_FS_REMOVE_FILE, :ACCESS_FS_MAKE_CHAR, :ACCESS_FS_MAKE_DIR,
                     :ACCESS_FS_MAKE_REG, :ACCESS_FS_MAKE_SOCK, :ACCESS_FS_MAKE_FIFO, :ACCESS_FS_MAKE_BLOCK,
                     :ACCESS_FS_MAKE_SYM, :ACCESS_FS_REFER, :ACCESS_FS_TRUNCATE, :ACCESS_FS_RESOLVE_UNIX,
                     :ACCESS_FS_IOCTL_DEV,
                     :ACCESS_NET_BIND_TCP, :ACCESS_NET_CONNECT_TCP, :ACCESS_NET_BIND_UDP,
                     :ACCESS_NET_CONNECT_SEND_UDP, :SCOPE_ABSTRACT_UNIX_SOCKET, :MINIMUM_ABI,
                     :MINIMUM_FULL_NETWORK_ABI, :WRITE_ACCESS_FS, :FILE_WRITE_ACCESS_FS, :FILE_READ_ACCESS_FS,
                     :READ_ACCESS_FS

    class << self
      # Landlock cannot restrict chmod, chown, extended attributes or timestamp
      # changes. Callers requiring Bubblewrap-equivalent write isolation must
      # compensate for these limitations:
      # https://www.kernel.org/doc/html/latest/userspace-api/landlock.html#filesystem-flags
      sig { returns(T::Boolean) }
      def full_write_isolation? = false

      sig { returns(T::Boolean) }
      def available?
        state == :available
      end

      sig { returns(Symbol) }
      def state
        @state ||= T.let(compute_state, T.nilable(Symbol))
      end

      sig { returns(T.nilable(Integer)) }
      def abi_version
        state
        @abi_version
      end

      # The Landlock ABI version provided by the running kernel, regardless of
      # whether Homebrew's Linux sandbox is enabled or usable.
      sig { returns(T.nilable(Integer)) }
      def kernel_abi_version
        require "fiddle"

        version = landlock_create_ruleset(nil, 0, CREATE_RULESET_VERSION)
        version if version.positive?
      rescue LoadError, Fiddle::DLError
        nil
      end

      sig { returns(T.nilable(String)) }
      def failure_reason
        case state
        when :available
          nil
        when :config_disabled
          "Landlock cannot be used because Linux sandboxing is disabled."
        when :missing_fiddle
          "Landlock requires Ruby's bundled Fiddle library."
        when :unsupported
          "Landlock is not supported by this Linux kernel."
        when :disabled
          "Landlock is disabled by this Linux kernel."
        when :unsupported_abi
          abi = @abi_version
          if abi
            "Landlock ABI #{MINIMUM_ABI} or later is required; found ABI #{abi}."
          else
            "Landlock ABI #{MINIMUM_ABI} or later is required."
          end
        else
          "Landlock is not available."
        end
      end

      sig { void }
      def reset_state!
        @state = T.let(nil, T.nilable(Symbol))
        @abi_version = T.let(nil, T.nilable(Integer))
      end

      sig { params(install_from_tests: T::Boolean).void }
      def ensure_installed!(install_from_tests: false); end

      sig { void }
      def configure!
        ensure_available!
      end

      sig { returns(T::Array[String]) }
      def configuration_commands = []

      sig { returns(T::Array[String]) }
      def configuration_command_messages = []

      sig { returns(T.nilable(String)) }
      def install_command = nil

      sig { returns(T::Boolean) }
      def nested_sandbox? = false

      sig { params(attributes: T.nilable(String), size: Integer, flags: Integer).returns(Integer) }
      def landlock_create_ruleset(attributes, size, flags)
        @landlock_create_ruleset ||= T.let(
          Fiddle::Function.new(
            Fiddle.dlopen(nil)["syscall"],
            [Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_UINT],
            Fiddle::TYPE_LONG,
          ),
          T.nilable(Fiddle::Function),
        )
        @landlock_create_ruleset.call(CREATE_RULESET_SYSCALL, attributes, size, flags)
      end

      sig { params(ruleset_fd: Integer, type: Integer, attributes: String, flags: Integer).returns(Integer) }
      def landlock_add_rule(ruleset_fd, type, attributes, flags)
        @landlock_add_rule ||= T.let(
          Fiddle::Function.new(
            Fiddle.dlopen(nil)["syscall"],
            [Fiddle::TYPE_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
            Fiddle::TYPE_LONG,
          ),
          T.nilable(Fiddle::Function),
        )
        @landlock_add_rule.call(ADD_RULE_SYSCALL, ruleset_fd, type, attributes, flags)
      end

      sig { params(ruleset_fd: Integer, flags: Integer).returns(Integer) }
      def landlock_restrict_self(ruleset_fd, flags)
        @landlock_restrict_self ||= T.let(
          Fiddle::Function.new(
            Fiddle.dlopen(nil)["syscall"],
            [Fiddle::TYPE_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_UINT],
            Fiddle::TYPE_LONG,
          ),
          T.nilable(Fiddle::Function),
        )
        @landlock_restrict_self.call(RESTRICT_SELF_SYSCALL, ruleset_fd, flags)
      end

      sig { returns(Integer) }
      def set_no_new_privileges
        @prctl ||= T.let(
          Fiddle::Function.new(
            Fiddle.dlopen(nil)["prctl"],
            [Fiddle::TYPE_INT, Fiddle::TYPE_ULONG, Fiddle::TYPE_ULONG, Fiddle::TYPE_ULONG, Fiddle::TYPE_ULONG],
            Fiddle::TYPE_INT,
          ),
          T.nilable(Fiddle::Function),
        )
        @prctl.call(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)
      end

      sig { params(path: String).returns(Integer) }
      def open_path(path)
        @open ||= T.let(
          Fiddle::Function.new(
            Fiddle.dlopen(nil)["open"],
            [Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT,
          ),
          T.nilable(Fiddle::Function),
        )
        @open.call(path, O_PATH | O_CLOEXEC)
      end

      sig { params(file_descriptor: Integer).returns(Integer) }
      def close_file_descriptor(file_descriptor)
        @close ||= T.let(
          Fiddle::Function.new(
            Fiddle.dlopen(nil)["close"],
            [Fiddle::TYPE_INT],
            Fiddle::TYPE_INT,
          ),
          T.nilable(Fiddle::Function),
        )
        @close.call(file_descriptor)
      end

      sig { returns(Integer) }
      def last_error
        Fiddle.last_error
      end

      private

      sig { void }
      def ensure_available!
        return if available?

        raise failure_reason || "Landlock is not available."
      end

      sig { returns(Symbol) }
      def compute_state
        return :config_disabled unless Homebrew::EnvConfig.sandbox_linux?

        begin
          require "fiddle"
        rescue LoadError
          return :missing_fiddle
        end

        version = kernel_abi_version
        if version
          @abi_version = T.let(version, T.nilable(Integer))
          if version >= MINIMUM_ABI
            :available
          else
            :unsupported_abi
          end
        else
          case last_error
          when Errno::ENOSYS::Errno then :unsupported
          when Errno::EOPNOTSUPP::Errno then :disabled
          else                               :unavailable
          end
        end
      end
    end

    sig { params(profile: SandboxProfile).void }
    def initialize(profile)
      super
      @writable_paths = T.let([], T::Array[String])
      @readable_paths = T.let([], T::Array[String])
      @error_pipe_path = T.let(nil, T.nilable(String))
      @deny_all_network = T.let(false, T::Boolean)
      @deny_read = T.let(false, T::Boolean)
    end

    sig { params(args: T::Array[T.any(String, ::Pathname)], tmpdir: String).returns(T::Array[T.any(String, ::Pathname)]) }
    def command(args, tmpdir)
      paths = writable_paths
      @writable_paths = paths.keys | [File::NULL, tmpdir]
      @writable_paths.each { |path| prepare_writable_path(path, paths.fetch(path, :subpath)) }
      denied_read_paths = self.denied_read_paths
      @readable_paths = readable_paths(denied_read_paths)
      @deny_read = denied_read_paths.any?
      @deny_all_network = deny_all_network?
      @error_pipe_path = File.join(tmpdir, "socket")
      args
    end

    sig { void }
    def apply!
      abi = self.class.abi_version
      if !abi || abi < MINIMUM_ABI
        raise self.class.failure_reason || "Landlock ABI #{MINIMUM_ABI} or later is required."
      end

      if @deny_all_network && abi < MINIMUM_FULL_NETWORK_ABI
        opoo "Landlock ABI #{MINIMUM_FULL_NETWORK_ABI} or later is required to deny all network access; " \
             "found ABI #{abi}. Applying the network restrictions supported by this kernel."
      end

      attributes, handled_access_fs, allowed_write_access_fs = ruleset_attributes(abi)
      ruleset_fd = self.class.landlock_create_ruleset(attributes, attributes.bytesize, 0)
      raise_system_call_error("landlock_create_ruleset") if ruleset_fd.negative?

      begin
        # PTY allocation opens `/dev/ptmx` read-write, then configures its
        # dynamically allocated `/dev/pts/*` slave with device ioctls:
        # https://github.com/torvalds/linux/blob/master/drivers/tty/pty.c
        # https://www.kernel.org/doc/html/latest/userspace-api/landlock.html#ioctl-support
        pty_access = ACCESS_FS_WRITE_FILE
        pty_access |= ACCESS_FS_IOCTL_DEV if abi >= 5
        pty_access |= ACCESS_FS_READ_FILE if @deny_read

        # `/dev/full` is Linux's standard ENOSPC test device. Opening it with
        # `fopen(..., "w")` also requires Landlock's truncate right:
        # https://github.com/torvalds/linux/blob/master/drivers/char/mem.c
        # POSIX shared memory and message queues use `/dev/shm` and
        # `/dev/mqueue`. These grants retain normal kernel permissions but do
        # not provide Bubblewrap's private IPC namespace:
        # https://github.com/bminor/glibc/blob/master/sysdeps/posix/shm-directory.c
        # https://www.kernel.org/doc/html/latest/filesystems/mqueue.html
        device_path_rules = T.let({
          "/dev/full"   => FILE_WRITE_ACCESS_FS,
          "/dev/mqueue" => allowed_write_access_fs,
          "/dev/ptmx"   => pty_access,
          "/dev/pts"    => pty_access,
          "/dev/shm"    => allowed_write_access_fs,
          "/dev/tty"    => pty_access,
        }, T::Hash[String, Integer])
        device_path_rules.each do |path, allowed_access|
          next unless File.exist?(path)

          add_path_rule(ruleset_fd, path, allowed_access)
        end

        error_pipe_path = @error_pipe_path
        if @deny_all_network && abi >= 9 && error_pipe_path
          add_path_rule(ruleset_fd, error_pipe_path, ACCESS_FS_RESOLVE_UNIX)
        end
        @readable_paths.each do |path|
          allowed_access = File.directory?(path) ? READ_ACCESS_FS : FILE_READ_ACCESS_FS
          add_path_rule(ruleset_fd, path, allowed_access)
        end
        @writable_paths.each do |path|
          allowed_access = if File.directory?(path)
            allowed_write_access_fs
          else
            allowed_write_access_fs & FILE_WRITE_ACCESS_FS
          end
          add_path_rule(ruleset_fd, path, allowed_access & handled_access_fs)
        end

        raise_system_call_error("prctl") if self.class.set_no_new_privileges.negative?
        if self.class.landlock_restrict_self(ruleset_fd, 0).negative?
          raise_system_call_error("landlock_restrict_self")
        end
      ensure
        close_file_descriptor(ruleset_fd)
      end
    end

    private

    sig { params(abi: Integer).returns([String, Integer, Integer]) }
    def ruleset_attributes(abi)
      allowed_access_fs = WRITE_ACCESS_FS
      allowed_access_fs |= ACCESS_FS_REFER if abi >= 2
      allowed_access_fs |= ACCESS_FS_TRUNCATE if abi >= 3
      handled_access_fs = allowed_access_fs
      # IOCTL_DEV is available from ABI 5 and deliberately remains absent from
      # allowed path rules, denying device ioctls opened inside the sandbox:
      # https://www.kernel.org/doc/html/latest/userspace-api/landlock.html#ioctl-support
      handled_access_fs |= ACCESS_FS_IOCTL_DEV if abi >= 5
      handled_access_fs |= READ_ACCESS_FS if @deny_read
      handled_access_fs |= ACCESS_FS_RESOLVE_UNIX if @deny_all_network && abi >= 9

      # Optional ruleset fields are appended as `__u64` members, so only pass
      # the prefix needed for features supported by the running kernel.
      attributes = [handled_access_fs]
      if @deny_all_network && abi >= 4
        handled_access_net = ACCESS_NET_BIND_TCP | ACCESS_NET_CONNECT_TCP
        handled_access_net |= ACCESS_NET_BIND_UDP | ACCESS_NET_CONNECT_SEND_UDP if abi >= MINIMUM_FULL_NETWORK_ABI
        attributes << handled_access_net
        attributes << SCOPE_ABSTRACT_UNIX_SOCKET if abi >= 6
      end

      [attributes.pack("Q*"), handled_access_fs, allowed_access_fs]
    end

    sig { params(ruleset_fd: Integer, path: String, allowed_access: Integer).void }
    def add_path_rule(ruleset_fd, path, allowed_access)
      path_fd = open_path(path)
      result = self.class.landlock_add_rule(
        ruleset_fd,
        RULE_PATH_BENEATH,
        # The packed UAPI struct has no padding or reserved field: one `__u64`
        # access mask followed by one `__s32` file descriptor.
        [allowed_access, path_fd].pack("Ql"),
        0,
      )
      raise_system_call_error("landlock_add_rule") if result.negative?
    ensure
      close_file_descriptor(path_fd) if path_fd
    end

    sig { returns(T::Array[::Pathname]) }
    def denied_read_paths
      profile_paths(allow: false, operation: "file-read").filter_map do |path|
        pathname = ::Pathname.new(path)
        pathname.lstat
        pathname
      rescue Errno::ENOENT
        nil
      end
    end

    sig { params(denied_paths: T::Array[::Pathname]).returns(T::Array[String]) }
    def readable_paths(denied_paths)
      return [] if denied_paths.empty? || denied_paths.include?(root_path)

      root_path.children.sort.each_with_object([]) do |path, paths|
        add_readable_path(path, denied_paths, paths)
      end
    end

    sig { params(path: ::Pathname, denied_paths: T::Array[::Pathname], paths: T::Array[String]).void }
    def add_readable_path(path, denied_paths, paths)
      return if denied_paths.include?(path)

      path_stat = path.lstat
      return if path_stat.symlink?

      if path_stat.directory? && denied_paths.any? { |denied_path| denied_path.ascend.include?(path) }
        path.children.sort.each { |child| add_readable_path(child, denied_paths, paths) }
      else
        paths << path.to_s
      end
    rescue Errno::EACCES, Errno::ENOENT
      nil
    end

    sig { returns(::Pathname) }
    def root_path
      ::Pathname.new("/")
    end

    sig { params(path: String).returns(Integer) }
    def open_path(path)
      file_descriptor = self.class.open_path(path)
      raise_system_call_error("open") if file_descriptor.negative?

      file_descriptor
    end

    sig { params(file_descriptor: Integer).void }
    def close_file_descriptor(file_descriptor)
      raise_system_call_error("close") if self.class.close_file_descriptor(file_descriptor).negative?
    end

    sig { params(operation: String).void }
    def raise_system_call_error(operation)
      raise SystemCallError.new(operation, self.class.last_error)
    end
  end
end
