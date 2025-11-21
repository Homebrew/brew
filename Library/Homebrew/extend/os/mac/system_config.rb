# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "system_command"

module OS
  module Mac
    module SystemConfig
      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::SystemConfig) }

        sig { returns(String) }
        def describe_clang
          return "N/A" if ::SystemConfig.clang.null?

          clang_build_info = ::SystemConfig.clang_build.null? ? "(parse error)" : ::SystemConfig.clang_build
          "#{::SystemConfig.clang} build #{clang_build_info}"
        end

        def xcode
          @xcode ||= if MacOS::Xcode.installed?
            xcode = MacOS::Xcode.version.to_s
            xcode += " => #{MacOS::Xcode.prefix}" unless MacOS::Xcode.default_prefix?
            xcode
          end
        end

        def clt
          @clt ||= MacOS::CLT.version if MacOS::CLT.installed?
        end

        def core_tap_config(out = $stdout)
          dump_tap_config(CoreTap.instance, out)
          dump_tap_config(CoreCaskTap.instance, out)
        end

        sig { returns(T.nilable(String)) }
        def metal_toolchain
          @metal_toolchain ||= if MacOS::Xcode.installed? || MacOS::CLT.installed?
            result = SystemCommand.run("xcrun", args: ["metal", "-v"], print_stderr: false, print_stdout: false)
            "present" if result.success?
          end
        end

        def dump_verbose_config(out = $stdout)
          super
          out.puts "macOS: #{MacOS.full_version}-#{kernel}"
          out.puts "CLT: #{clt || "N/A"}"
          out.puts "Xcode: #{xcode || "N/A"}"
          # Metal Toolchain is a separate install starting with Xcode 26.
          if MacOS::Xcode.installed? && MacOS::Xcode.version >= "26.0"
            out.puts "Metal Toolchain: #{metal_toolchain || "N/A"}"
          end
          out.puts "Rosetta 2: #{::Hardware::CPU.in_rosetta2?}" if ::Hardware::CPU.physical_cpu_arm64?
        end
      end
    end
  end
end
SystemConfig.singleton_class.prepend(OS::Mac::SystemConfig::ClassMethods)
