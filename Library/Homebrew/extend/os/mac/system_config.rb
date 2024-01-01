# typed: true
# frozen_string_literal: true

require "system_command"

module SystemConfig
  class << self
    include SystemCommand::Mixin

    undef describe_clang

    sig { returns(String) }
    def describe_clang
      return "N/A" if clang.null?

      clang_build_info = clang_build.null? ? "(parse error)" : clang_build
      "#{clang} build #{clang_build_info}"
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

    def dump_verbose_config(out = $stdout)
      dump_generic_verbose_config(out)
      out.puts "macOS: #{MacOS.full_version}-#{kernel}"
      out.puts "CLT: #{clt || "N/A"}"
      out.puts "Xcode: #{xcode || "N/A"}"
      out.puts "Rosetta 2: #{Hardware::CPU.in_rosetta2?}" if Hardware::CPU.physical_cpu_arm64?
    end
  end
end
