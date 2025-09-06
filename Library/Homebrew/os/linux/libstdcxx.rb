# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    # Helper functions for querying libstdc++ information.
    module Libstdcxx
      SONAME = "libstdc++.so.6"
      SYSTEM_LIBDIRS = %w[/lib64 /lib /usr/lib64 /usr/lib].freeze
      private_constant :SYSTEM_LIBDIRS

      sig { returns(Version) }
      def self.system_version
        @system_version ||= T.let(nil, T.nilable(Version))
        @system_version ||= if (path = system_path) &&
                               (version = File.realpath(path)[%r{/libstdc\+\+\.so\.(\d+(?:\.\d+)*)$}, 1])
          Version.new(version)
        else
          Version::NULL
        end
      end

      sig { returns(T::Boolean) }
      def self.below_ci_version?
        system_version < LINUX_LIBSTDCXX_CI_VERSION
      end

      sig { returns(T.nilable(String)) }
      private_class_method def self.system_path
        if (ldconfig = which("ldconfig"))
          path = Utils.popen_read(ldconfig, "-p")[%r{=> (/.*/#{Regexp.escape(SONAME)})$}o, 1]
          return path if path.present? && File.file?(path) && Pathname(path).dylib?
        end
        if (gcc = ::DevelopmentTools.host_gcc_path).executable?
          path = Utils.popen_read(gcc, "--print-file-name=#{SONAME}").strip
          return path if path.start_with?("/") && File.file?(path) && Pathname(path).dylib?
        end
        libdirs = SYSTEM_LIBDIRS.filter_map { |path| File.realpath(path) if File.directory?(path) }
        libdirs.uniq!
        Find.find(*libdirs).find do |path|
          path = Pathname(path)
          path.basename.to_s == SONAME && path.file? && path.dylib? && path.arch_compatible?(::Hardware::CPU.arch)
        end
      end
    end
  end
end
