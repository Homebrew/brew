# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/native_library"

module OS
  module Mac
    module FFI
      # LaunchServices.framework wrapper
      module LaunchServices
        extend NativeLibrary

        use_library(
          "/System/Library/Frameworks/CoreServices.framework/Versions/A/" \
          "Frameworks/LaunchServices.framework/Versions/A/LaunchServices",
        )

        # LaunchServices/LSQuarantine.h:
        #   extern const CFStringRef kLSQuarantineAgentNameKey;
        sig { returns(Fiddle::Pointer) }
        def self.quarantine_agent_name_key = constant("kLSQuarantineAgentNameKey", dereference: true)

        # LaunchServices/LSQuarantine.h:
        #   extern const CFStringRef kLSQuarantineTypeKey;
        sig { returns(Fiddle::Pointer) }
        def self.quarantine_type_key = constant("kLSQuarantineTypeKey", dereference: true)

        # LaunchServices/LSQuarantine.h:
        #   extern const CFStringRef kLSQuarantineTypeWebDownload;
        sig { returns(Fiddle::Pointer) }
        def self.quarantine_type_web_download = constant("kLSQuarantineTypeWebDownload", dereference: true)

        # LaunchServices/LSQuarantine.h:
        #   extern const CFStringRef kLSQuarantineDataURLKey;
        sig { returns(Fiddle::Pointer) }
        def self.quarantine_data_url_key = constant("kLSQuarantineDataURLKey", dereference: true)

        # LaunchServices/LSQuarantine.h:
        #   extern const CFStringRef kLSQuarantineOriginURLKey;
        sig { returns(Fiddle::Pointer) }
        def self.quarantine_origin_url_key = constant("kLSQuarantineOriginURLKey", dereference: true)
      end
    end
  end
end
