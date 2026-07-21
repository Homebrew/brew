# typed: strict
# frozen_string_literal: true

module Utils
  module Clang
    sig {
      params(
        config_dir:     Pathname,
        macos_version:  T.any(String, MacOSVersion),
        kernel_version: T.any(String, Integer),
        arch:           Symbol,
      ).void
    }
    def self.write_system_config_files(config_dir:, macos_version:, kernel_version:, arch:)
      config_dir.mkpath
      arches = Set.new([:arm64, :x86_64, :aarch64, arch])
      sysroot = if macos_version.blank? || MacOS.version > macos_version
        "#{MacOS::CLT::PKG_PATH}/SDKs/MacOSX.sdk"
      else
        "#{MacOS::CLT::PKG_PATH}/SDKs/MacOSX#{macos_version}.sdk"
      end

      { darwin: kernel_version, macosx: macos_version }.each do |system, version|
        arches.each do |target_arch|
          (config_dir/"#{target_arch}-apple-#{system}#{version}.cfg").atomic_write <<~CONFIG
            -isysroot #{sysroot}
          CONFIG
        end
      end
    end
  end
end
