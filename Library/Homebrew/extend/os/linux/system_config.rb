# typed: strict
# frozen_string_literal: true

require "compilers"
require "os/linux/glibc"
require "os/linux/libstdcxx"
require "system_command"

module OS
  module Linux
    module SystemConfig
      module ClassMethods
        include SystemCommand::Mixin

        HOST_RUBY_PATH = "/usr/bin/ruby"

        sig { returns(T.any(String, Version)) }
        def host_glibc_version
          version = OS::Linux::Glibc.system_version
          return "N/A" if version.null?

          version
        end

        sig { returns(T.any(String, Version)) }
        def host_libstdcxx_version
          version = OS::Linux::Libstdcxx.system_version
          return "N/A" if version.null?

          version
        end

        sig { returns(String) }
        def host_gcc_version
          gcc = ::DevelopmentTools.host_gcc_path
          return "N/A" unless gcc.executable?

          Utils.popen_read(gcc, "--version")[/ (\d+\.\d+\.\d+)/, 1] || "N/A"
        end

        sig { params(formula: T.any(::Pathname, String)).returns(T.any(String, PkgVersion)) }
        def formula_linked_version(formula)
          return "N/A" if Homebrew::EnvConfig.no_install_from_api? && !CoreTap.instance.installed?

          Formulary.factory(formula).any_installed_version || "N/A"
        rescue FormulaUnavailableError
          "N/A"
        end

        sig { returns(String) }
        def host_ruby_version
          out, _, status = system_command(HOST_RUBY_PATH, args: ["-e", "puts RUBY_VERSION"], print_stderr: false).to_a
          return "N/A" unless status.success?

          out
        end

        sig { params(out: T.any(File, StringIO, IO)).void }
        def dump_verbose_config(out = $stdout)
          kernel = Utils.safe_popen_read("uname", "-mors").chomp
          super
          out.puts "Kernel: #{kernel}"
          out.puts "OS: #{OS::Linux.os_version}"
          out.puts "WSL: #{OS::Linux.wsl_version}" if OS::Linux.wsl?
          out.puts "Host glibc: #{host_glibc_version}"
          out.puts "Host libstdc++: #{host_libstdcxx_version}"
          out.puts "#{::DevelopmentTools.host_gcc_path}: #{host_gcc_version}"
          out.puts "/usr/bin/ruby: #{host_ruby_version}" if RUBY_PATH != HOST_RUBY_PATH
          ["glibc", ::CompilerSelector.preferred_gcc, OS::LINUX_PREFERRED_GCC_RUNTIME_FORMULA, "xorg"].each do |f|
            out.puts "#{f}: #{formula_linked_version(f)}"
          end
        end
      end
    end
  end
end

SystemConfig.singleton_class.prepend(OS::Linux::SystemConfig::ClassMethods)
