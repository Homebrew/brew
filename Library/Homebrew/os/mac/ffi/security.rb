# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/core_foundation"
require "os/mac/ffi/objective_c"

module OS
  module Mac
    module FFI
      # Security.framework code-signing wrapper.
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
            block: T.proc.params(result: Fiddle::Pointer).returns(Integer),
          ).returns(T.nilable(Fiddle::Pointer))
        }
        private_class_method def self.retained_pointer(&block)
          result = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
          result[0, Fiddle::SIZEOF_VOIDP] = [0].pack("J")
          return unless yield(result).zero?

          pointer = result.ptr
          return if pointer.null?

          CoreFoundation.autorelease(pointer)
        end

        sig { params(path: String).returns(T.nilable(Fiddle::Pointer)) }
        private_class_method def self.static_code(path)
          path_string = CoreFoundation.string_create(File.expand_path(path))
          return if path_string.null?

          path_url = CoreFoundation.url_create_with_file_system_path(path_string)
          return if path_url.null?

          retained_pointer do |result|
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
          code = static_code(path)
          return if code.nil?

          requirement = retained_pointer do |result|
            # https://developer.apple.com/documentation/security/seccodecopydesignatedrequirement%28_%3A_%3A_%3A%29
            function(
              "SecCodeCopyDesignatedRequirement",
              FUNCTION_ARGUMENT_TYPES,
              Fiddle::TYPE_INT,
            ).call(code, 0, result)
          end
          return if requirement.nil?

          # Validate sealed content against its own identity before trusting it.
          # https://developer.apple.com/documentation/security/secstaticcodecheckvalidity%28_%3A_%3A_%3A%29
          return unless function(
            "SecStaticCodeCheckValidity",
            FUNCTION_ARGUMENT_TYPES,
            Fiddle::TYPE_INT,
          ).call(code, VALIDATION_FLAGS, requirement).zero?

          requirement_string = retained_pointer do |result|
            function(
              "SecRequirementCopyString",
              FUNCTION_ARGUMENT_TYPES,
              Fiddle::TYPE_INT,
            ).call(requirement, 0, result)
          end
          return if requirement_string.nil?

          ObjectiveC.message_send(
            requirement_string,
            "UTF8String",
            [],
            Fiddle::TYPE_VOIDP,
          ).to_s
        end

        sig { params(path: String, requirement: String).returns(T.nilable(T::Boolean)) }
        def self.requirement_match(path, requirement)
          code = static_code(path)
          return if code.nil?

          requirement_string = CoreFoundation.string_create(requirement)
          return if requirement_string.null?

          compiled_requirement = retained_pointer do |result|
            # https://developer.apple.com/documentation/security/1394522-secrequirementcreatewithstring
            function(
              "SecRequirementCreateWithString",
              FUNCTION_ARGUMENT_TYPES,
              Fiddle::TYPE_INT,
            ).call(requirement_string, 0, result)
          end
          return if compiled_requirement.nil?

          status = function(
            "SecStaticCodeCheckValidity",
            FUNCTION_ARGUMENT_TYPES,
            Fiddle::TYPE_INT,
          ).call(code, VALIDATION_FLAGS, compiled_requirement)
          return true if status.zero?

          false if status == REQUIREMENT_FAILED_STATUS
        end
      end
    end
  end
end
