# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/native_library"

module OS
  module Mac
    module FFI
      # CoreFoundation.framework wrapper
      module CoreFoundation
        extend NativeLibrary

        use_library "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"

        sig { params(ptr: Fiddle::Pointer).returns(Fiddle::Pointer) }
        def self.autorelease(ptr)
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
    end
  end
end
