# typed: strict
# frozen_string_literal: true

require "fiddle"

module OS
  module Mac
    # Wrapping module for FFI calls to system libraries.
    module FFI
      # NativeLibrary provides helper methods for loading system libraries and accessing functions and constants.
      # Functions and constants are cached so they only need to be looked up once.
      module NativeLibrary
        private

        sig { params(path: String).void }
        def use_library(path)
          @library_path = T.let(path.freeze, T.nilable(String))
        end

        sig { returns(Fiddle::Handle) }
        def handle
          @handle ||= T.let(Fiddle.dlopen(T.must(@library_path)), T.nilable(Fiddle::Handle))
        end

        sig { params(name: String, argument_types: T::Array[Integer], return_type: Integer).returns(Fiddle::Function) }
        def function(name, argument_types, return_type)
          @functions ||= T.let({}, T.nilable(T::Hash[String, Fiddle::Function]))
          @functions[name] ||= Fiddle::Function.new(handle[name], argument_types, return_type)
        end

        sig { params(name: String, dereference: T::Boolean).returns(Fiddle::Pointer) }
        def constant(name, dereference: false)
          @constants ||= T.let({}, T.nilable(T::Hash[[String, T::Boolean], Fiddle::Pointer]))
          @constants[[name, dereference]] ||= begin
            pointer = Fiddle::Pointer.new(handle[name])
            dereference ? pointer.ptr : pointer
          end
        end
      end

      extend NativeLibrary

      use_library "/usr/lib/libSystem.B.dylib"

      # mach-o/dyld.h:
      #   bool _dyld_shared_cache_contains_path(const char* path);
      sig { params(path: String).returns(T::Boolean) }
      def self.dyld_shared_cache_contains_path(path)
        function(
          "_dyld_shared_cache_contains_path",
          [Fiddle::TYPE_CONST_STRING],
          Fiddle::TYPE_BOOL,
        ).call(path)
      end

      # CoreFoundation.framework wrapper
      module CoreFoundation
        extend NativeLibrary

        use_library "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"

        sig { params(ptr: Fiddle::Pointer).returns(Fiddle::Pointer) }
        private_class_method def self.autorelease(ptr)
          return ptr if ptr.null?

          # CoreFoundation/CFBase.h:
          #   void CFRelease(CFTypeRef cf);
          ptr.free = function("CFRelease", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          ptr
        end

        # CoreFoundation/CFDictionary.h:
        #   extern const CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks;
        sig { returns(Fiddle::Pointer) }
        def self.type_dictionary_key_call_backs = constant("kCFTypeDictionaryKeyCallBacks")

        # CoreFoundation/CFDictionary.h:
        #   extern const CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks
        sig { returns(Fiddle::Pointer) }
        def self.type_dictionary_value_call_backs = constant("kCFTypeDictionaryValueCallBacks")

        # CoreFoundation/CFURL.h:
        #   extern const CFStringRef kCFURLQuarantinePropertiesKey;
        sig { returns(Fiddle::Pointer) }
        def self.url_quarantine_properties_key = constant("kCFURLQuarantinePropertiesKey", dereference: true)

        # CoreFoundation/CFString.h:
        #   CFStringRef CFStringCreateWithCString(CFAllocatorRef alloc, const char *cStr, CFStringEncoding encoding);
        sig { params(string: String).returns(Fiddle::Pointer) }
        def self.string_create(string)
          cf_encoding = case string.encoding
          when Encoding::UTF_8
            0x08000100 # kCFStringEncodingUTF8
          when Encoding::US_ASCII
            0x0600 # kCFStringEncodingASCII
          when Encoding::ASCII_8BIT, Encoding::ISO8859_1
            # ASCII-8BIT could be anything, so just use Latin-1
            0x0201 # kCFStringEncodingISOLatin1
          else
            # Try convert to UTF-8 and move on
            string = string.encode(Encoding::UTF_8)
            0x08000100
          end

          autorelease(
            function(
              "CFStringCreateWithCString",
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_UINT32_T],
              Fiddle::TYPE_VOIDP,
            ).call(nil, string, cf_encoding),
          )
        end

        # CoreFoundation/CFDictionary.h:
        #   CFDictionaryRef CFDictionaryCreate(
        #     CFAllocatorRef allocator,
        #     const void **keys,
        #     const void **values,
        #     CFIndex numValues,
        #     const CFDictionaryKeyCallBacks *keyCallBacks,
        #     const CFDictionaryValueCallBacks *valueCallBacks);
        sig { params(hash: T::Hash[Fiddle::Pointer, Fiddle::Pointer]).returns(Fiddle::Pointer) }
        def self.dictionary_create(hash)
          size = Fiddle::SIZEOF_VOIDP * hash.size
          Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE) do |keys|
            Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE) do |values|
              # Convert array of pointers to continous stream of pointers in the C buffer
              keys[0, size] = hash.keys.pack("J*")
              values[0, size] = hash.values.pack("J*")
              return autorelease(
                function(
                  "CFDictionaryCreate",
                  [
                    Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP,
                    Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP
                  ],
                  Fiddle::TYPE_VOIDP,
                ).call(
                  nil, keys, values, hash.size, type_dictionary_key_call_backs, type_dictionary_value_call_backs
                ),
              )
            end
          end
        end

        # CoreFoundation/CFURL.h:
        #   CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef allocator,
        #     CFStringRef filePath, CFURLPathStyle pathStyle, Boolean isDirectory);
        sig { params(path: Fiddle::Pointer).returns(Fiddle::Pointer) }
        def self.url_create_with_file_system_path(path)
          autorelease(
            function(
              "CFURLCreateWithFileSystemPath",
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_BOOL],
              Fiddle::TYPE_VOIDP,
            ).call(nil, path, 0, false),
          )
        end

        # CoreFoundation/CFURL.h:
        #   Boolean CFURLSetResourcePropertyForKey(CFURLRef url, CFStringRef key, CFTypeRef value, CFErrorRef *error);
        sig { params(url: Fiddle::Pointer, key: Fiddle::Pointer, value: Fiddle::Pointer).returns(T::Boolean) }
        def self.url_set_resource_property_for_key(url, key, value)
          function(
            "CFURLSetResourcePropertyForKey",
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_BOOL,
          ).call(url, key, value, nil)
        end
      end

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
