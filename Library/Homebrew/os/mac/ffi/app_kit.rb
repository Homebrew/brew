# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/native_library"
require "os/mac/ffi/objective_c"

module OS
  module Mac
    module FFI
      # AppKit.framework wrapper
      module AppKit
        extend NativeLibrary

        use_library "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

        # AppKit/NSRunningApplication.h:
        #   + (NSRunningApplication *)runningApplicationWithProcessIdentifier:(pid_t)pid;
        #   @property(readonly, copy) NSString *bundleIdentifier;
        #
        # Returns `nil` if the process is not an application known to Launch Services.
        sig { params(pid: Integer).returns(T.nilable(String)) }
        def self.bundle_identifier_for_pid(pid)
          # Ensure the framework is loaded so the Objective-C runtime knows the class.
          handle

          application = ObjectiveC.message_send(
            ObjectiveC.class_get("NSRunningApplication"),
            "runningApplicationWithProcessIdentifier:",
            [Fiddle::TYPE_INT],
            Fiddle::TYPE_VOIDP,
            pid,
          )
          return if application.null?

          bundle_identifier = ObjectiveC.message_send(application, "bundleIdentifier", [], Fiddle::TYPE_VOIDP)
          return if bundle_identifier.null?

          ObjectiveC.message_send(bundle_identifier, "UTF8String", [], Fiddle::TYPE_VOIDP).to_s
        end
      end
    end
  end
end
