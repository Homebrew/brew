# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "tempfile"
require "utils/shell"
require "hardware"
require "os/linux/glibc"
require "os/linux/kernel"

module OS
  module Linux
    module Diagnostic
      module Checks
        extend T::Helpers

        requires_ancestor { DinrusBrew::Diagnostic::Checks }

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
            Если у Вас на этой машине отсутствуют права администратора,
            создайте директорию и установите переменную среды DINRUSBREW_TEMP,
            например:
              install -d -m 1755 ~/tmp
              #{Utils::Shell.set_variable_in_profile("DINRUSBREW_TEMP", "~/tmp")}
          EOS
        end

        def check_tmpdir_executable
          f = Tempfile.new(%w[homebrew_check_tmpdir_executable .sh], DINRUSBREW_TEMP)
          f.write "#!/bin/sh\n"
          f.chmod 0700
          f.close
          return if system T.must(f.path)

          <<~EOS
            В директории #{DINRUSBREW_TEMP} запрещено выполнять программы.
            Вероятно, она смонтирована как "noexec". Пожалуйста, установите DINRUSBREW_TEMP
            в #{Utils::Shell.profile} в другую директорию, например:
              export DINRUSBREW_TEMP=~/tmp
              echo 'export DINRUSBREW_TEMP=~/tmp' >> #{Utils::Shell.profile}
          EOS
        ensure
          f&.unlink
        end

        def check_umask_not_zero
          return unless File.umask.zero?

          <<~EOS
            umask установлена в 000. Директории, созданные DinrusBrew не могут быть
            world-writable. Эту проблему можно решить, добавив "umask 002" в
            #{Utils::Shell.profile}:
              echo 'umask 002' >> #{Utils::Shell.profile}
          EOS
        end

        def check_supported_architecture
          return if Hardware::CPU.arch == :x86_64

          <<~EOS
            Архитектура ЦПБ (#{Hardware::CPU.arch}) не поддерживается. Поддерживаются только
            архитектуры ЦПБ x86_64. Вы не сможете использовать бинарные пакеты (бутыли).
            #{please_create_pull_requests}
          EOS
        end

        def check_glibc_minimum_version
          return unless OS::Linux::Glibc.below_minimum_version?

          <<~EOS
            Библиотека glibc #{OS::Linux::Glibc.system_version} на вашей системе
            очень устарела. Поддерживается только glibc #{OS::Linux::Glibc.minimum_version}
            или более свежая.
            #{please_create_pull_requests}
            Рекомендуем обновить её до новой версии посредством менеджера пакетов
            вашего дистрибутива, проведя апгрейд до последней версии или
            изменив дисстрибутив.
          EOS
        end

        def check_kernel_minimum_version
          return unless OS::Linux::Kernel.below_minimum_version?

          <<~EOS
            Ваше ядро Linux #{OS.kernel_version} очень устарело.
            Поддерживается только ядро #{OS::Linux::Kernel.minimum_version} или новее.
            Вы не сможете использовать бинарные пакеты (бутыли).
            #{please_create_pull_requests}
            Рекомендуем обновить её до новой версии посредством менеджера пакетов
            вашего дистрибутива, проведя апгрейд до последней версии или
            изменив дисстрибутив.
          EOS
        end

        def check_linuxbrew_core
          return unless DinrusBrew::EnvConfig.no_install_from_api?
          return unless CoreTap.instance.linuxbrew_core?

          <<~EOS
            Ключевая репозитория Linux всё ещё linuxbrew-core.
            Нужно выполнить `brew update`, чтобы обновиться до homebrew-core.
          EOS
        end

        def check_linuxbrew_bottle_domain
          return unless DinrusBrew::EnvConfig.bottle_domain.include?("linuxbrew")

          <<~EOS
            В вашем DINRUSBREW_BOTTLE_DOMAIN всё ещё содержится "linuxbrew".
            Нужно удалить его (настроить, чтобы не было linuxbrew,
            например, заменив его на homebrew).
          EOS
        end

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
           Обнаружены формулы, компонуемые к GCC через путь с версией. Эти формулы создают
           вероятность сломов после обновления GCC. Нужно для этих формул выполнить `brew reinstall`:
          EOS
        end
      end
    end
  end
end

DinrusBrew::Diagnostic::Checks.prepend(OS::Linux::Diagnostic::Checks)
