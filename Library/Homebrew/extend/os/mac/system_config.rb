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
          super
          @xcode = T.let(nil, T.nilable(String))
          @clt = T.let(nil, T.nilable(String))
        end

        sig { returns(String) }
        def describe_clang
          return "N/A" if clang.null?

          clang_build_info = clang_build.null? ? "(parse error)" : clang_build
          "#{clang} build #{clang_build_info}"
        end

        sig { returns(T.nilable(String)) }
        def xcode
          @xcode ||= if MacOS::Xcode.installed?
            xcode = MacOS::Xcode.version.to_s
            xcode += " => #{MacOS::Xcode.prefix}" unless MacOS::Xcode.default_prefix?
            xcode
          end
        end

        sig { returns(T.nilable(String)) }
        def clt
          @clt ||= if MacOS::CLT.installed?
            MacOS::CLT.version.to_s.presence || "unknown"
          end
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
        def macos_config(out = $stdout)
          out.puts "macOS: #{MacOS.full_version}-#{kernel}"
          clt_version = clt || "N/A"
          out.puts "CLT: #{clt_version}"
          xcode_version = xcode || "N/A"
          out.puts "Xcode: #{xcode_version}"
          # Metal Toolchain is a separate install starting with Xcode 26.
          if ::Hardware::CPU.arm64? && MacOS::Xcode.installed? && MacOS::Xcode.version >= "26.0"
            metal_version = metal_toolchain || "N/A"
            out.puts "Metal Toolchain: #{metal_version}"
          end
          out.puts "Rosetta 2: #{::Hardware::CPU.in_rosetta2?}" if ::Hardware::CPU.physical_cpu_arm64?
        end

        sig { returns(T::Array[Symbol]) }
        def config_sections
          super + [:macos_config]
        end
      end
    end
  end
end

SystemConfig.singleton_class.prepend(OS::Mac::SystemConfig::ClassMethods)
