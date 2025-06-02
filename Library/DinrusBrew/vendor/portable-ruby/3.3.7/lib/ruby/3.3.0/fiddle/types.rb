# frozen_string_literal: true
module Fiddle
  # Adds Windows type aliases to the including class for use with
  # Fiddle::Importer.
  #
  # The aliases added are:
  # * ATOM
  # * BOOL
  # * BYTE
  # * DWORD
  # * DWORD32
  # * DWORD64
  # * HANDLE
  # * HDC
  # * HINSTANCE
  # * HWND
  # * LPCSTR
  # * LPSTR
  # * PBYTE
  # * PDWORD
  # * PHANDLE
  # * PVOID
  # * PWORD
  # * UCHAR
  # * UINT
  # * ULONG
  # * WORD
  module Win32Types
    def included(m) # :nodoc:
      # https://docs.microsoft.com/en-us/windows/win32/winprog/windows-data-types
      m.module_eval{
        typealias "ATOM", "WORD"
        typealias "BOOL", "int"
        typealias "BYTE", "unsigned char"
        typealias "DWORD", "unsigned long"
        typealias "DWORD32", "uint32_t"
        typealias "DWORD64", "uint64_t"
        typealias "HANDLE", "PVOID"
        typealias "HDC", "HANDLE"
        typealias "HINSTANCE", "HANDLE"
        typealias "HWND", "HANDLE"
        typealias "LPCSTR", "const char *"
        typealias "LPSTR", "char *"
        typealias "PBYTE", "BYTE *"
        typealias "PDWORD", "DWORD *"
        typealias "PHANDLE", "HANDLE *"
        typealias "PVOID", "void *"
        typealias "PWORD", "WORD *"
        typealias "UCHAR", "unsigned char"
        typealias "UINT", "unsigned int"
        typealias "ULONG", "unsigned long"
        typealias "WORD", "unsigned short"
      }
    end
    module_function :included
  end

  # Adds basic type aliases to the including class for use with Fiddle::Importer.
  #
  # The aliases added are +uint+ and +u_int+ (<tt>unsigned int</tt>) and
  # +ulong+ and +u_long+ (<tt>unsigned long</tt>)
  module BasicTypes
    def included(m) # :nodoc:
      m.module_eval{
        typealias "uint", "unsigned int"
        typealias "u_int", "unsigned int"
        typealias "ulong", "unsigned long"
        typealias "u_long", "unsigned long"
      }
    end
    module_function :included
  end
end
