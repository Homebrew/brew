# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/core_foundation"
require "os/mac/ffi/objective_c"

module OS
  module Mac
    module FFI
      module Foundation
        sig { params(path: String).returns(T.nilable(String)) }
        def self.trash_item(path)
          result_url = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
          error = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
          result_url[0, Fiddle::SIZEOF_VOIDP] = [0].pack("J")
          error[0, Fiddle::SIZEOF_VOIDP] = [0].pack("J")

          success = ObjectiveC.message_send(
            ObjectiveC.message_send(
              ObjectiveC.class_get("NSFileManager"),
              "defaultManager",
              [],
              Fiddle::TYPE_VOIDP,
            ),
            "trashItemAtURL:resultingItemURL:error:",
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_BOOL,
            ObjectiveC.message_send(
              ObjectiveC.class_get("NSURL"),
              "fileURLWithPath:",
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_VOIDP,
              CoreFoundation.string_create(path),
            ),
            result_url,
            error,
          )
          return unless success

          ObjectiveC.message_send(
            ObjectiveC.message_send(result_url.ptr, "path", [], Fiddle::TYPE_VOIDP),
            "UTF8String",
            [],
            Fiddle::TYPE_VOIDP,
          ).to_s
        end

        sig { params(paths: T::Array[String]).returns([T::Array[String], T::Array[String]]) }
        def self.trash_paths(paths)
          trashed = T.let([], T::Array[String])
          untrashable = T.let([], T::Array[String])

          paths.each do |path|
            trashed_path = trash_item(path)
            if trashed_path
              trashed << trashed_path
            else
              untrashable << path
            end
          rescue
            untrashable << path
          end

          [trashed, untrashable]
        end
      end
    end
  end
end
