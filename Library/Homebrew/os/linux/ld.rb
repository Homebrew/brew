# typed: true
# frozen_string_literal: true

module OS
  module Linux
    # Helper functions for querying `ld` information.
    #
    # @api private
    module Ld
      module_function

      sig { returns(String) }
      def sysconfdir
        fallback_sysconfdir = "/etc"

        brewed_ld_so = HOMEBREW_PREFIX/"lib/ld.so"
        return fallback_sysconfdir unless brewed_ld_so.exist?

        ld_so_output = Utils.popen_read(brewed_ld_so, "--list-diagnostics")
        return fallback_sysconfdir unless $CHILD_STATUS.success?

        match = ld_so_output.match(/path.sysconfdir="(.+)"/)
        return fallback_sysconfdir unless match

        match.captures.compact.first
      end

      sig { returns(T::Array[String]) }
      def system_dirs
        system_dirs = []

        brewed_ld_so = HOMEBREW_PREFIX/"lib/ld.so"
        return system_dirs unless brewed_ld_so.exist?

        ld_so_output = Utils.popen_read(brewed_ld_so, "--list-diagnostics").split("\n")
        return system_dirs unless $CHILD_STATUS.success?

        ld_so_output.each do |line|
          match = line.match(/path.system_dirs\[0x.*\]="(.*)"/)
          next unless match

          system_dirs << match.captures.compact.first
        end

        system_dirs
      end

      sig { params(conf_path: T.any(String, Pathname)).returns(T::Array[String]) }
      def library_paths(conf_path = Pathname(sysconfdir)/"ld.so.conf")
        conf_file = Pathname(conf_path)
        paths = Set.new
        directory = conf_file.realpath.dirname

        conf_file.readlines.each do |line|
          # Remove comments and leading/trailing whitespace
          line.strip!
          line.sub!(/\s*#.*$/, "")

          if line.start_with?(/\s*include\s+/)
            include_path = Pathname(line.sub(/^\s*include\s+/, "")).expand_path
            wildcard = include_path.absolute? ? include_path : directory/include_path

            Dir.glob(wildcard.to_s).each do |include_file|
              paths += library_paths(include_file)
            end
          elsif line.empty?
            next
          else
            paths << line
          end
        end

        paths.to_a
      end
    end
  end
end
