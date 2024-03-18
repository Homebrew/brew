# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking Adobe Air archives.
  class Air
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      [".air"]
    end

    def self.can_extract?(path)
      mime_type = "application/vnd.adobe.air-application-installer-package+zip"
      path.magic_number.match?(/.{59}#{Regexp.escape(mime_type)}/)
    end

    def dependencies
      @dependencies ||= [Cask::CaskLoader.load("adobe-air")]
    end

    AIR_APPLICATION_INSTALLER =
      "/Applications/Utilities/Adobe AIR Application Installer.app/Contents/MacOS/Adobe AIR Application Installer"

    private_constant :AIR_APPLICATION_INSTALLER

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! AIR_APPLICATION_INSTALLER,
                      args:    ["-silent", "-location", unpack_dir, path],
                      verbose:
    end
  end
end
