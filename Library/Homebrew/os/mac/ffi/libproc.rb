# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/native_library"

module OS
  module Mac
    module FFI
      # libproc wrapper
      module LibProc
        extend NativeLibrary

        use_library "/usr/lib/libproc.dylib"

        # sys/proc_info.h:
        #   #define PROC_PIDT_SHORTBSDINFO 13
        PROC_PIDT_SHORTBSDINFO = 13

        # sys/proc_info.h:
        #   struct proc_bsdshortinfo {
        #     uint32_t pbsi_pid, pbsi_ppid, pbsi_pgid, pbsi_status;
        #     char pbsi_comm[16];
        #     uint32_t pbsi_flags;
        #     uid_t pbsi_uid; gid_t pbsi_gid; uid_t pbsi_ruid; ...
        #   };
        PROC_BSDSHORTINFO_SIZE = 64
        PROC_BSDSHORTINFO_PPID_OFFSET = 4
        PROC_BSDSHORTINFO_RUID_OFFSET = 44
        private_constant :PROC_BSDSHORTINFO_SIZE, :PROC_BSDSHORTINFO_PPID_OFFSET, :PROC_BSDSHORTINFO_RUID_OFFSET

        # Returns `nil` if the process does not exist or cannot be inspected.
        # Returns `0` for `launchd`, which has no parent.
        sig { params(pid: Integer).returns(T.nilable(Integer)) }
        def self.parent_pid(pid)
          short_bsd_info_field(pid, PROC_BSDSHORTINFO_PPID_OFFSET)
        end

        # The real user ID, which decides whether the current user may signal
        # the process.
        #
        # Returns `nil` if the process does not exist or cannot be inspected.
        sig { params(pid: Integer).returns(T.nilable(Integer)) }
        def self.real_uid(pid)
          short_bsd_info_field(pid, PROC_BSDSHORTINFO_RUID_OFFSET)
        end

        # libproc.h:
        #   int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
        #
        # Unlike `PROC_PIDTBSDINFO`, this flavor is not restricted to processes
        # owned by the current user, so e.g. the ancestry walk can pass through
        # the root-owned `login` between the shell and its terminal.
        sig { params(pid: Integer, offset: Integer).returns(T.nilable(Integer)) }
        private_class_method def self.short_bsd_info_field(pid, offset)
          buffer = Fiddle::Pointer.malloc(PROC_BSDSHORTINFO_SIZE, Fiddle::RUBY_FREE)
          size = function(
            "proc_pidinfo",
            [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_UINT64_T, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT,
          ).call(pid, PROC_PIDT_SHORTBSDINFO, 0, buffer, PROC_BSDSHORTINFO_SIZE)
          return if size != PROC_BSDSHORTINFO_SIZE

          buffer[offset, Fiddle::SIZEOF_INT].unpack1("L")
        end
      end
    end
  end
end
