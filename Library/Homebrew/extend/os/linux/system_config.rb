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

        sig { returns(T.nilable(String)) }
        def windows_version
          return unless OS.wsl?

          cmd = Kernel.which("cmd.exe", ORIGINAL_PATHS) || ::Pathname.new("/mnt/c/Windows/System32/cmd.exe")
          return unless cmd.executable?

          windows_registry_version(cmd) || Utils.popen_read(cmd, "/d", "/c", "ver", err: :close)
                                                .delete("\r")
                                                .lines
                                                .map(&:strip)
                                                .find { |line| line.start_with?("Microsoft Windows") }
        end

        sig { params(cmd: ::Pathname).returns(T.nilable(String)) }
        def windows_registry_version(cmd)
          values = windows_registry_values(cmd)
          product_name = values["ProductName"]
          build = values["CurrentBuildNumber"]
          return if product_name.blank? || build.blank?

          product_name = product_name.sub(/\AWindows 10\b/, "Windows 11") if build.to_i >= 22_000
          build += ".#{values["UBR"]}" if values["UBR"].present?

          version = values["DisplayVersion"] || values["ReleaseId"]
          return "#{product_name} [#{build}]" if version.blank?

          "#{product_name} (#{version}) [#{build}]"
        end

        sig { params(cmd: ::Pathname).returns(T::Hash[String, String]) }
        def windows_registry_values(cmd)
          output = Utils.popen_read(cmd, "/d", "/c", "reg", "query",
                                    "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
                                    err: :close)

          output.each_line.with_object({}) do |line, values|
            match = line.delete("\r").match(/^\s*(\S+)\s+REG_\S+\s+(.+?)\s*$/)
            next if match.nil?

            key = match[1]
            value = match[2]
            next if key.nil? || value.nil?

            values[key] = value.start_with?("0x") ? value.to_i(16).to_s : value
          end
        end

        sig { params(out: T.any(File, StringIO, IO)).void }
        def linux_config(out = $stdout)
          out.puts "Kernel: #{Utils.safe_popen_read("uname", "-mors").chomp}"
          out.puts "OS: #{OS::Linux.os_version}"
          if OS.wsl?
            out.puts "WSL: #{OS::Linux.wsl_version}"
            windows = windows_version
            out.puts "Windows: #{windows}" if windows
          end
          out.puts "Host glibc: #{host_glibc_version}"
          out.puts "Host libstdc++: #{host_libstdcxx_version}"
          out.puts "#{::DevelopmentTools.host_gcc_path}: #{host_gcc_version}"
          out.puts "/usr/bin/ruby: #{host_ruby_version}" if RUBY_PATH != HOST_RUBY_PATH
          ["glibc", ::CompilerSelector.preferred_gcc, OS::LINUX_PREFERRED_GCC_RUNTIME_FORMULA, "xorg"].each do |f|
            out.puts "#{f}: #{formula_linked_version(f)}"
          end
        end

        sig { returns(T::Array[Symbol]) }
        def config_sections
          super + [:linux_config]
        end
      end
    end
  end
end

SystemConfig.singleton_class.prepend(OS::Linux::SystemConfig::ClassMethods)
