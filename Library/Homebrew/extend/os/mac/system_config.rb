# typed: strict
# frozen_string_literal: true

require "system_command"

module OS
  module Mac
    module SystemConfig
      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::SystemConfig) }

        sig { void }
        def initialize
          @xcode = T.let(nil, T.nilable(String))
          @clt = T.let(nil, T.nilable(Version))
        end

        sig { returns(String) }
        def describe_clang
          return "N/A" if ::SystemConfig.clang.null?

          clang_build_info = ::SystemConfig.clang_build.null? ? "(parse error)" : ::SystemConfig.clang_build
          "#{::SystemConfig.clang} build #{clang_build_info}"
        end

        sig { returns(T.nilable(String)) }
        def xcode
          @xcode ||= if MacOS::Xcode.installed?
            xcode = MacOS::Xcode.version.to_s
            xcode += " => #{MacOS::Xcode.prefix}" unless MacOS::Xcode.default_prefix?
            xcode
          end
        end

        sig { returns(T.nilable(Version)) }
        def clt
          @clt ||= MacOS::CLT.version if MacOS::CLT.installed?
        end

        sig { params(out: T.any(File, StringIO, IO)).void }
        def core_tap_config(out = $stdout)
          dump_tap_config(CoreTap.instance, out)
          dump_tap_config(CoreCaskTap.instance, out)
        end

        sig { returns(T.nilable(String)) }
        def metal_toolchain
          return unless ::Hardware::CPU.arm64?

          @metal_toolchain ||= T.let(nil, T.nilable(String))
          @metal_toolchain ||= if MacOS::Xcode.installed? || MacOS::CLT.installed?
            result = SystemCommand.run("xcrun", args: ["--find", "metal"],
                                       print_stderr: false, print_stdout: false)
            pattern = /MetalToolchain-v(?<major>\d+)\.(?<letter>\d+)\.(?<build>\d+)\.(?<minor>\d+)/
            if result.success? && (m = result.stdout.match(pattern))
              letter = ("A".ord - 1 + m[:letter].to_i).chr
              "#{m[:major]}.#{m[:minor]} (#{m[:major]}#{letter}#{m[:build]})"
            end
          end
        end

        sig { params(out: T.any(File, StringIO, IO)).void }
        def dump_verbose_config(out = $stdout)
          super
          out.puts "macOS: #{MacOS.full_version}-#{kernel}"
          out.puts "CLT: #{clt || "N/A"}"
          out.puts "Xcode: #{xcode || "N/A"}"
          # Metal Toolchain is a separate install starting with Xcode 26.
          if ::Hardware::CPU.arm64? && MacOS::Xcode.installed? && MacOS::Xcode.version >= "26.0"
            out.puts "Metal Toolchain: #{metal_toolchain || "N/A"}"
          end
          out.puts "Rosetta 2: #{::Hardware::CPU.in_rosetta2?}" if ::Hardware::CPU.physical_cpu_arm64?
        end
      end
    end
  end
end
SystemConfig.singleton_class.prepend(OS::Mac::SystemConfig::ClassMethods)
