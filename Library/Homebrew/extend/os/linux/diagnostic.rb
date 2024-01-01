# typed: true
# frozen_string_literal: true

require "tempfile"
require "utils/shell"
require "hardware"
require "os/linux/glibc"
require "os/linux/kernel"

module Homebrew
  module Diagnostic
    class Checks
      undef fatal_preinstall_checks, supported_configuration_checks

      def fatal_preinstall_checks
        %w[
          check_access_directories
          check_linuxbrew_core
          check_linuxbrew_bottle_domain
        ].freeze
      end

      def supported_configuration_checks
        %w[
          check_glibc_minimum_version
          check_kernel_minimum_version
          check_supported_architecture
        ].freeze
      end

      def check_tmpdir_sticky_bit
        message = generic_check_tmpdir_sticky_bit
        return if message.nil?

        message + <<~EOS
          If you don't have administrative privileges on this machine,
          create a directory and set the HOMEBREW_TEMP environment variable,
          for example:
            install -d -m 1755 ~/tmp
            #{Utils::Shell.set_variable_in_profile("HOMEBREW_TEMP", "~/tmp")}
        EOS
      end

      def check_tmpdir_executable
        f = Tempfile.new(%w[homebrew_check_tmpdir_executable .sh], HOMEBREW_TEMP)
        f.write "#!/bin/sh\n"
        f.chmod 0700
        f.close
        return if system T.must(f.path)

        <<~EOS
          The directory #{HOMEBREW_TEMP} does not permit executing
          programs. It is likely mounted as "noexec". Please set HOMEBREW_TEMP
          in your #{Utils::Shell.profile} to a different directory, for example:
            export HOMEBREW_TEMP=~/tmp
            echo 'export HOMEBREW_TEMP=~/tmp' >> #{Utils::Shell.profile}
        EOS
      ensure
        f&.unlink
      end

      def check_xdg_data_dirs
        xdg_data_dirs = ENV.fetch("XDG_DATA_DIRS", nil)
        return if xdg_data_dirs.blank? || xdg_data_dirs.split("/").include?(HOMEBREW_PREFIX/"share")

        <<~EOS
          Homebrew's share was not found in your XDG_DATA_DIRS but you have
          this variable set to include other locations.
          Some programs like `vapigen` may not work correctly.
          Consider adding Homebrew's share directory to XDG_DATA_DIRS like so:
            echo 'export XDG_DATA_DIRS="#{HOMEBREW_PREFIX}/share:$XDG_DATA_DIRS"' >> #{Utils::Shell.profile}
        EOS
      end

      def check_umask_not_zero
        return unless File.umask.zero?

        <<~EOS
          umask is currently set to 000. Directories created by Homebrew cannot
          be world-writable. This issue can be resolved by adding "umask 002" to
          your #{Utils::Shell.profile}:
            echo 'umask 002' >> #{Utils::Shell.profile}
        EOS
      end

      def check_supported_architecture
        return if Hardware::CPU.arch == :x86_64

        <<~EOS
          Your CPU architecture (#{Hardware::CPU.arch}) is not supported. We only support
          x86_64 CPU architectures. You will be unable to use binary packages (bottles).
          #{please_create_pull_requests}
        EOS
      end

      def check_glibc_minimum_version
        return unless OS::Linux::Glibc.below_minimum_version?

        <<~EOS
          Your system glibc #{OS::Linux::Glibc.system_version} is too old.
          We only support glibc #{OS::Linux::Glibc.minimum_version} or later.
          #{please_create_pull_requests}
          We recommend updating to a newer version via your distribution's
          package manager, upgrading your distribution to the latest version,
          or changing distributions.
        EOS
      end

      def check_kernel_minimum_version
        return unless OS::Linux::Kernel.below_minimum_version?

        <<~EOS
          Your Linux kernel #{OS.kernel_version} is too old.
          We only support kernel #{OS::Linux::Kernel.minimum_version} or later.
          You will be unable to use binary packages (bottles).
          #{please_create_pull_requests}
          We recommend updating to a newer version via your distribution's
          package manager, upgrading your distribution to the latest version,
          or changing distributions.
        EOS
      end

      def check_linuxbrew_core
        return unless Homebrew::EnvConfig.no_install_from_api?
        return unless CoreTap.instance.linuxbrew_core?

        <<~EOS
          Your Linux core repository is still linuxbrew-core.
          You must `brew update` to update to homebrew-core.
        EOS
      end

      def check_linuxbrew_bottle_domain
        return unless Homebrew::EnvConfig.bottle_domain.include?("linuxbrew")

        <<~EOS
          Your HOMEBREW_BOTTLE_DOMAIN still contains "linuxbrew".
          You must unset it (or adjust it to not contain linuxbrew
          e.g. by using homebrew instead).
        EOS
      end

      def check_gcc_dependent_linkage
        gcc_dependents = Formula.installed.select do |formula|
          next false unless formula.tap&.core_tap?

          # FIXME: This includes formulae that have no runtime dependency on GCC.
          formula.recursive_dependencies.map(&:name).include? "gcc"
        rescue TapFormulaUnavailableError
          false
        end
        return if gcc_dependents.empty?

        badly_linked = gcc_dependents.select do |dependent|
          keg = Keg.new(dependent.prefix)
          keg.binary_executable_or_library_files.any? do |binary|
            paths = binary.rpaths
            versioned_linkage = paths.any? { |path| path.match?(%r{lib/gcc/\d+$}) }
            unversioned_linkage = paths.any? { |path| path.match?(%r{lib/gcc/current$}) }

            versioned_linkage && !unversioned_linkage
          end
        end
        return if badly_linked.empty?

        inject_file_list badly_linked, <<~EOS
          Formulae which link to GCC through a versioned path were found. These formulae
          are prone to breaking when GCC is updated. You should `brew reinstall` these formulae:
        EOS
      end
    end
  end
end
