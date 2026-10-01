# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/core_foundation"
require "os/mac/ffi/objective_c"

module OS
  module Mac
    module FFI
      # Security.framework code-signing wrapper.
      #
      # Every Core Foundation object is scoped to a {CoreFoundation::ReleasePool}
      # so it is released before returning to the caller. Security.framework
      # objects especially must never be left to GC-time release: their
      # destructors log via `os_log`, which crashes when run on the child side
      # of `fork` (e.g. in `Utils.popen`).
      # https://github.com/Homebrew/brew/issues/23606
      module Security
        extend NativeLibrary

        use_library "/System/Library/Frameworks/Security.framework/Versions/A/Security"

        FUNCTION_ARGUMENT_TYPES = T.let(
          [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_VOIDP].freeze,
          T::Array[Integer],
        )

        # Validate every architecture, nested code and strict bundle structure.
        # https://developer.apple.com/documentation/security/static-code-validation-flags
        VALIDATION_FLAGS = T.let(((1 << 0) | (1 << 3) | (1 << 4)).freeze, Integer)

        # https://developer.apple.com/documentation/security/errseccsreqfailed
        REQUIREMENT_FAILED_STATUS = -67050

        sig {
          params(
            pool:  CoreFoundation::ReleasePool,
            block: T.proc.params(result: Fiddle::Pointer).returns(Integer),
          ).returns(T.nilable(Fiddle::Pointer))
        }
        private_class_method def self.retained_pointer(pool, &block)
          # Plain malloc scratch for the out-parameter, safely left to GC;
          # only the Core Foundation object it yields needs pool-scoped release.
          result = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
          result[0, Fiddle::SIZEOF_VOIDP] = [0].pack("J")
          return unless yield(result).zero?

          pointer = result.ptr
          return if pointer.null?

          pool.track(pointer)
        end

        sig { params(path: String, pool: CoreFoundation::ReleasePool).returns(T.nilable(Fiddle::Pointer)) }
        private_class_method def self.static_code(path, pool)
          path_string = pool.track(CoreFoundation.string_create(File.expand_path(path)))
          return if path_string.null?

          path_url = pool.track(CoreFoundation.url_create_with_file_system_path(path_string))
          return if path_url.null?

          retained_pointer(pool) do |result|
            # https://developer.apple.com/documentation/security/secstaticcodecreatewithpath%28_%3A_%3A_%3A%29
            function(
              "SecStaticCodeCreateWithPath",
              FUNCTION_ARGUMENT_TYPES,
              Fiddle::TYPE_INT,
            ).call(path_url, 0, result)
          end
        end

        # A designated requirement is macOS's durable identity for recognising
        # successive versions of the same signed code.
        # https://developer.apple.com/documentation/security/applying-code-requirements
        sig { params(path: String).returns(T.nilable(String)) }
        def self.designated_requirement(path)
          CoreFoundation.with_release_pool do |pool|
            code = static_code(path, pool)
            next if code.nil?

            requirement = retained_pointer(pool) do |result|
              # https://developer.apple.com/documentation/security/seccodecopydesignatedrequirement%28_%3A_%3A_%3A%29
              function(
                "SecCodeCopyDesignatedRequirement",
                FUNCTION_ARGUMENT_TYPES,
                Fiddle::TYPE_INT,
              ).call(code, 0, result)
            end
            next if requirement.nil?

            # Validate sealed content against its own identity before trusting it.
            # https://developer.apple.com/documentation/security/secstaticcodecheckvalidity%28_%3A_%3A_%3A%29
            next unless function(
              "SecStaticCodeCheckValidity",
              FUNCTION_ARGUMENT_TYPES,
              Fiddle::TYPE_INT,
            ).call(code, VALIDATION_FLAGS, requirement).zero?

            requirement_string = retained_pointer(pool) do |result|
              function(
                "SecRequirementCopyString",
                FUNCTION_ARGUMENT_TYPES,
                Fiddle::TYPE_INT,
              ).call(requirement, 0, result)
            end
            next if requirement_string.nil?

            ObjectiveC.message_send(
              requirement_string,
              "UTF8String",
              [],
              Fiddle::TYPE_VOIDP,
            ).to_s
          end
        end

        sig { params(path: String, requirement: String).returns(T.nilable(T::Boolean)) }
        def self.requirement_match(path, requirement)
          CoreFoundation.with_release_pool do |pool|
            code = static_code(path, pool)
            next if code.nil?

            requirement_string = pool.track(CoreFoundation.string_create(requirement))
            next if requirement_string.null?

            compiled_requirement = retained_pointer(pool) do |result|
              # https://developer.apple.com/documentation/security/1394522-secrequirementcreatewithstring
              function(
                "SecRequirementCreateWithString",
                FUNCTION_ARGUMENT_TYPES,
                Fiddle::TYPE_INT,
              ).call(requirement_string, 0, result)
            end
            next if compiled_requirement.nil?

            status = function(
              "SecStaticCodeCheckValidity",
              FUNCTION_ARGUMENT_TYPES,
              Fiddle::TYPE_INT,
            ).call(code, VALIDATION_FLAGS, compiled_requirement)
            next true if status.zero?

            false if status == REQUIREMENT_FAILED_STATUS
          end
        end
      end
    end
  end
end
