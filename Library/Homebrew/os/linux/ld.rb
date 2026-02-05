# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    # Helper functions for querying `ld` information.
    module Ld
      # This is a list of known paths to the host dynamic linker on Linux if
      # the host glibc is new enough. Brew will fail to create a symlink for
      # ld.so if the host linker cannot be found in this list.
      DYNAMIC_LINKERS = %w[
        /lib64/ld-linux-x86-64.so.2
        /lib64/ld64.so.2
        /lib/ld-linux.so.3
        /lib/ld-linux.so.2
        /lib/ld-linux-aarch64.so.1
        /lib/ld-linux-armhf.so.3
        /system/bin/linker64
        /system/bin/linker
      ].freeze

      # The path to the system's dynamic linker or `nil` if not found
      sig { returns(T.nilable(::Pathname)) }
      def self.system_ld_so
        @system_ld_so ||= T.let(nil, T.nilable(::Pathname))
        @system_ld_so ||= begin
          linker = DYNAMIC_LINKERS.find { |s| File.executable? s }
          Pathname(linker) if linker
        end
      end

      sig { params(brewed: T::Boolean).returns(String) }
      def self.ld_so_diagnostics(brewed: true)
        @ld_so_diagnostics ||= T.let({}, T.nilable(T::Hash[Pathname, T.nilable(String)]))

        ld_so_target = if brewed
          ld_so = HOMEBREW_PREFIX/"lib/ld.so"
          return "" unless ld_so.exist?

          ld_so.readlink
        else
          ld_so = system_ld_so
          return "" unless ld_so&.exist?

          ld_so
        end

        @ld_so_diagnostics[ld_so_target] ||= begin
          ld_so_output = Utils.popen_read(ld_so, "--list-diagnostics")
          ld_so_output if $CHILD_STATUS.success?
        end

        @ld_so_diagnostics[ld_so_target].to_s
      end

      sig { params(brewed: T::Boolean).returns(String) }
      def self.sysconfdir(brewed: true)
        fallback_sysconfdir = "/etc"

        match = ld_so_diagnostics(brewed:).match(/path.sysconfdir="(.+)"/)
        return fallback_sysconfdir unless match

        match.captures.compact.first || fallback_sysconfdir
      end

      sig { params(brewed: T::Boolean).returns(T::Array[String]) }
      def self.system_dirs(brewed: true)
        dirs = []

        ld_so_diagnostics(brewed:).split("\n").each do |line|
          match = line.match(/path.system_dirs\[0x.*\]="(.*)"/)
          next unless match

          dirs << match.captures.compact.first
        end

        dirs
      end

      sig { params(conf_path: T.any(::Pathname, String), brewed: T::Boolean).returns(T::Array[String]) }
      def self.library_paths(conf_path = "ld.so.conf", brewed: true)
        conf_file = Pathname(sysconfdir(brewed:))/conf_path
        return [] unless conf_file.exist?
        return [] unless conf_file.file?
        return [] unless conf_file.readable?

        @library_paths_cache ||= T.let({}, T.nilable(T::Hash[String, T::Array[String]]))
        cache_key = conf_file.to_s
        if (cached_library_path_contents = @library_paths_cache[cache_key])
          return cached_library_path_contents
        end

        paths = Set.new
        directory = conf_file.realpath.dirname

        conf_file.open("r") do |file|
          file.each_line do |line|
            # Remove comments and leading/trailing whitespace
            line.strip!
            line.sub!(/\s*#.*$/, "")

            if line.start_with?(/\s*include\s+/)
              wildcard = Pathname(line.sub(/^\s*include\s+/, "")).expand_path(directory)

              Dir.glob(wildcard.to_s).each do |include_file|
                paths += library_paths(include_file)
              end
            elsif line.empty?
              next
            else
              paths << line
            end
          end
        end

        @library_paths_cache[cache_key] = paths.to_a
      end
    end
  end
end
