# typed: strict
# frozen_string_literal: true

require "tempfile"
require "utils/shell"
require "hardware"
require "os/linux/glibc"
require "os/linux/kernel"

module OS
  module Linux
    module Diagnostic
      # Linux-specific diagnostic checks for Homebrew.
      module Checks
        extend T::Helpers

        requires_ancestor { Homebrew::Diagnostic::Checks }

        sig { returns(T::Array[String]) }
        def fatal_preinstall_checks
          %w[
            check_access_directories
            check_linuxbrew_core
            check_linuxbrew_bottle_domain
          ].freeze
        end

        sig { returns(T::Array[String]) }
        def supported_configuration_checks
          %w[
            check_glibc_minimum_version
            check_kernel_minimum_version
            check_supported_architecture
          ].freeze
        end

        sig { returns(T.nilable(String)) }
        def check_tmpdir_sticky_bit
          message = super
          return if message.nil?

          message + <<~EOS
            If you don't have administrative privileges on this machine,
            create a directory and set the `$HOMEBREW_TEMP` environment variable,
            for example:
              install -d -m 1755 ~/tmp
              #{Utils::Shell.set_variable_in_profile("HOMEBREW_TEMP", "~/tmp")}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_tmpdir_executable
          f = Tempfile.new(%w[homebrew_check_tmpdir_executable .sh], HOMEBREW_TEMP)
          f.write "#!/bin/sh\n"
          f.chmod 0700
          f.close
          return if system T.must(f.path)

          <<~EOS
            The directory #{HOMEBREW_TEMP} does not permit executing
            programs. It is likely mounted as "noexec". Please set `$HOMEBREW_TEMP`
            in your #{Utils::Shell.profile} to a different directory, for example:
              export HOMEBREW_TEMP=~/tmp
              echo 'export HOMEBREW_TEMP=~/tmp' >> #{Utils::Shell.profile}
          EOS
        ensure
          f&.unlink
        end

        sig { returns(T.nilable(String)) }
        def check_umask_not_zero
          return unless File.umask.zero?

          <<~EOS
            umask is currently set to 000. Directories created by Homebrew cannot
            be world-writable. This issue can be resolved by adding "umask 002" to
            your #{Utils::Shell.profile}:
              echo 'umask 002' >> #{Utils::Shell.profile}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_supported_architecture
          return if ::Hardware::CPU.intel?
          return if ::Hardware::CPU.arm64?

          <<~EOS
            Your CPU architecture (#{::Hardware::CPU.arch}) is not supported. We only support
            x86_64 or ARM64/AArch64 CPU architectures. You will be unable to use binary packages (bottles).

            #{support_tier_message(tier: 2)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_glibc_minimum_version
          return unless OS::Linux::Glibc.below_minimum_version?

          <<~EOS
            Your system glibc #{OS::Linux::Glibc.system_version} is too old.
            We only support glibc #{OS::Linux::Glibc.minimum_version} or later.

            We recommend updating to a newer version via your distribution's
            package manager, upgrading your distribution to the latest version,
            or changing distributions.

            #{support_tier_message(tier: :unsupported)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_glibc_version
          return unless OS::Linux::Glibc.below_ci_version?

          # We want to bypass this check in some tests.
          return if ENV["HOMEBREW_GLIBC_TESTING"]

          <<~EOS
            Your system glibc #{OS::Linux::Glibc.system_version} is too old.
            We will need to automatically install a newer version.

            We recommend updating to a newer version via your distribution's
            package manager, upgrading your distribution to the latest version,
            or changing distributions.

            #{support_tier_message(tier: 2)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_kernel_minimum_version
          return unless OS::Linux::Kernel.below_minimum_version?

          <<~EOS
            Your Linux kernel #{OS.kernel_version} is too old.
            We only support kernel #{OS::Linux::Kernel.minimum_version} or later.
            You will be unable to use binary packages (bottles).

            We recommend updating to a newer version via your distribution's
            package manager, upgrading your distribution to the latest version,
            or changing distributions.

            #{support_tier_message(tier: 3)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_linuxbrew_core
          return unless Homebrew::EnvConfig.no_install_from_api?
          return unless CoreTap.instance.linuxbrew_core?

          <<~EOS
            Your Linux core repository is still linuxbrew-core.
            You must either unset `$HOMEBREW_NO_INSTALL_FROM_API` or set
            the repository's remote to homebrew-core to update core formulae.
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_linuxbrew_bottle_domain
          return unless Homebrew::EnvConfig.bottle_domain.include?("linuxbrew")

          <<~EOS
            Your `$HOMEBREW_BOTTLE_DOMAIN` still contains "linuxbrew".
            You must unset it (or adjust it to not contain linuxbrew
            e.g. by using homebrew instead).
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_for_symlinked_home
          return unless File.symlink?("/home")

          <<~EOS
            Your /home directory is a symlink.
            This is known to cause issues with formula linking, particularly when installing
            multiple formulae that create symlinks in shared directories.

            While this may be a standard directory structure in some distributions
            (e.g. Fedora Silverblue) there are known issues as-is.

            If you encounter linking issues, you may need to manually create conflicting
            directories or use `brew link --overwrite` as a workaround.

            We'd welcome a PR to fix this functionality.
            See https://github.com/Homebrew/brew/issues/18036 for more context.

            #{support_tier_message(tier: 2)}
          EOS
        end

        sig { returns(T.nilable(String)) }
        def check_gcc_dependent_linkage
          gcc_dependents = ::Formula.installed.select do |formula|
            next false unless formula.tap&.core_tap?

            # FIXME: This includes formulae that have no runtime dependency on GCC.
            formula.recursive_dependencies.map(&:name).include? "gcc"
          rescue TapFormulaUnavailableError
            false
          end
          return if gcc_dependents.empty?

          badly_linked = gcc_dependents.select do |dependent|
            dependent_prefix = dependent.any_installed_prefix
            # Keg.new() may raise an error if it is not a directory.
            # As the result `brew doctor` may display `Error: <keg> is not a directory`
            # instead of proper `doctor` information.
            # There are other checks that test that, we can skip broken kegs.
            next if dependent_prefix.nil? || !dependent_prefix.exist? || !dependent_prefix.directory?

            keg = ::Keg.new(dependent_prefix)
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

        sig { returns(T.nilable(String)) }
        def check_cask_software_versions
          super
          add_info "Linux", OS::Linux.os_version

          nil
        end
      end
    end
  end
end

Homebrew::Diagnostic::Checks.prepend(OS::Linux::Diagnostic::Checks)
