# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking Adobe Air archives.
  class Air
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".air"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      mime_type = "application/vnd.adobe.air-application-installer-package+zip"
      path.magic_number.match?(/.{59}#{Regexp.escape(mime_type)}/)
    end

    sig { returns(T::Array[Cask::Cask]) }
    def dependencies
      @dependencies ||= T.let([Cask::CaskLoader.load("adobe-air")], T.nilable(T::Array[Cask::Cask]))
    end

    AIR_APPLICATION_INSTALLER =
      "/Applications/Utilities/Adobe AIR Application Installer.app/Contents/MacOS/Adobe AIR Application Installer"

    private_constant :AIR_APPLICATION_INSTALLER

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! AIR_APPLICATION_INSTALLER,
                      args:    ["-silent", "-location", unpack_dir, path],
                      verbose:
    end
  end
end
