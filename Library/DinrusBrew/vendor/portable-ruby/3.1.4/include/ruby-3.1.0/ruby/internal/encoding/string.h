#ifndef RUBY_INTERNAL_ENCODING_STRING_H              /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_STRING_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Routines to manipulate encodings of strings.
 */

#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/encoding/encoding.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/intern/string.h" /* rbimpl_strlen */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Identical to rb_enc_str_new(), except it additionally takes an encoding.
 *
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @param[in]  enc             Encoding of `ptr`.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An instance  of ::rb_cString,  of `len`  bytes length,  of `enc`
 *             encoding, whose contents are verbatim copy of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 * @note       `enc` can be a  null pointer.  It can also be  seen as a routine
 *             identical to rb_usascii_str_new() then.
 */
VALUE rb_enc_str_new(const char *ptr, long len, rb_encoding *enc);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to  rb_enc_str_new(), except  it assumes the  passed pointer  is a
 * pointer  to a  C string.  It can  also  be seen  as a  routine identical  to
 * rb_str_new_cstr(), except it additionally takes an encoding.
 *
 * @param[in]  ptr             A C string.
 * @param[in]  enc             Encoding of `ptr`.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An instance  of ::rb_cString, of `enc`  encoding, whose contents
 *             are verbatim copy of `ptr`.
 * @pre        `ptr` must not be a null pointer.
 * @pre        Because `ptr` is  a C string it  makes no sense for  `enc` to be
 *             something like UTF-32.
 * @note       `enc` can be a  null pointer.  It can also be  seen as a routine
 *             identical to rb_usascii_str_new_cstr() then.
 */
VALUE rb_enc_str_new_cstr(const char *ptr, rb_encoding *enc);

/**
 * Identical to rb_enc_str_new(),  except it takes a C string  literal.  It can
 * also  be seen  as  a  routine identical  to  rb_str_new_static(), except  it
 * additionally takes an encoding.
 *
 * @param[in]  ptr           A C string literal.
 * @param[in]  len           `strlen(ptr)`.
 * @param[in]  enc           Encoding of `ptr`.
 * @exception  rb_eArgError  `len` out of range of `size_t`.
 * @pre        `ptr` must be a C string constant.
 * @return     An instance  of ::rb_cString,  of `enc` encoding,  whose backend
 *             storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 * @note       `enc` can be a  null pointer.  It can also be  seen as a routine
 *             identical to rb_usascii_str_new_static() then.
 */
VALUE rb_enc_str_new_static(const char *ptr, long len, rb_encoding *enc);

/**
 * Identical to rb_enc_str_new(),  except it returns a "f"string.   It can also
 * be seen as a routine  identical to rb_interned_str(), except it additionally
 * takes an encoding.
 *
 * @param[in]  ptr           A memory region of `len` bytes length.
 * @param[in]  len           Length  of  `ptr`,  in bytes,  not  including  the
 *                           terminating NUL character.
 * @param[in]  enc           Encoding of `ptr`.
 * @exception  rb_eArgError  `len` is negative.
 * @return     A  found or  created instance  of ::rb_cString,  of `len`  bytes
 *             length, of `enc` encoding, whose  contents are identical to that
 *             of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 * @note       `enc` can be a null  pointer.
 */
VALUE rb_enc_interned_str(const char *ptr, long len, rb_encoding *enc);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to rb_enc_str_new_cstr(),  except it returns a  "f"string.  It can
 * also be  seen as  a routine identical  to rb_interned_str_cstr(),  except it
 * additionally takes an encoding.
 *
 * @param[in]  ptr           A memory region of `len` bytes length.
 * @param[in]  enc           Encoding of `ptr`.
 * @return     A found  or created instance  of ::rb_cString of `enc` encoding,
 *             whose contents are identical to that of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 * @note       `enc` can be a null  pointer.
 */
VALUE rb_enc_interned_str_cstr(const char *ptr, rb_encoding *enc);

/**
 * Counts  the number  of characters  of the  passed string,  according to  the
 * passed encoding.   This has to be  complicated.  The passed string  could be
 * invalid and/or broken.   This routine would scan from the  beginning til the
 * end, byte by byte, to seek out character boundaries.  Could be super slow.
 *
 * @param[in]  head  Leftmost pointer to the string.
 * @param[in]  tail  Rightmost pointer to the string.
 * @param[in]  enc   Encoding of the string.
 * @return     Number of characters exist in  `head` .. `tail`.  The definition
 *             of "character" depends on the passed `enc`.
 */
long rb_enc_strlen(const char *head, const char *tail, rb_encoding *enc);

/**
 * Queries the n-th character.  Like  rb_enc_strlen() this function can be fast
 * or slow depending on the contents.   Don't expect characters to be uniformly
 * distributed across the entire string.
 *
 * @param[in]  head  Leftmost pointer to the string.
 * @param[in]  tail  Rightmost pointer to the string.
 * @param[in]  nth   Requested index of characters.
 * @param[in]  enc   Encoding of the string.
 * @return     Pointer  to  the first  byte  of  the  character that  is  `nth`
 *             character  ahead  of `head`,  or  `tail`  if  there is  no  such
 *             character (OOB  etc).  The definition of  "character" depends on
 *             the passed `enc`.
 */
char *rb_enc_nth(const char *head, const char *tail, long nth, rb_encoding *enc);

/**
 * Identical to rb_enc_get_index(), except the return type.
 *
 * @param[in]  obj            Object in question.
 * @exception  rb_eTypeError  `obj` is incapable of having an encoding.
 * @return     `obj`'s encoding.
 */
VALUE rb_obj_encoding(VALUE obj);

/**
 * Identical to rb_str_cat(), except it additionally takes an encoding.
 *
 * @param[out]  str                 Destination object.
 * @param[in]   ptr                 Contents to append.
 * @param[in]   len                 Length of `src`, in bytes.
 * @param[in]   enc                 Encoding of `ptr`.
 * @exception   rb_eArgError        `len` is negative.
 * @exception   rb_eEncCompatError  `enc` is not compatible with `str`.
 * @return      The passed `dst`.
 * @post        The  contents  of  `ptr`  is copied,  transcoded  into  `dst`'s
 *              encoding, then pasted into `dst`'s end.
 */
VALUE rb_enc_str_buf_cat(VALUE str, const char *ptr, long len, rb_encoding *enc);

/**
 * Encodes the passed code point into a series of bytes.
 *
 * @param[in]  code             Code point.
 * @param[in]  enc              Target encoding scheme.
 * @exception  rb_eRangeError  `enc` does not glean `code`.
 * @return     An  instance  of ::rb_cString,  of  `enc`  encoding, whose  sole
 *             contents is `code` represented in `enc`.
 * @note       No way to encode code points bigger than UINT_MAX.
 *
 * @internal
 *
 * In  other languages,  APIs like  this  one could  be seen  as the  primitive
 * routines where encodings' "encode" feature are implemented.  However in case
 * of  Ruby this  is not  the primitive  one.  We  directly manipulate  encoded
 * strings.  Encoding conversion routines  transcode an encoded string directly
 * to another one; not via a code point array.
 */
VALUE rb_enc_uint_chr(unsigned int code, rb_encoding *enc);

/**
 * Identical  to   rb_external_str_new(),  except  it  additionally   takes  an
 * encoding.  However the  whole point of rb_external_str_new() is  to encode a
 * string  into default  external encoding.   Being able  to specify  arbitrary
 * encoding just ruins the designed purpose the function meseems.
 *
 * @param[in]  ptr           A memory region of `len` bytes length.
 * @param[in]  len           Length  of  `ptr`,  in bytes,  not  including  the
 *                           terminating NUL character.
 * @param[in]  enc           Target encoding scheme.
 * @exception  rb_eArgError  `len` is negative.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default  internal" to  `enc` is  fully defined  over the  given
 *             contents, then the  return value is a string  of `enc` encoding,
 *             whose contents are the converted  ones.  Otherwise the string is
 *             a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 *
 * @internal
 *
 * @shyouhei has  no idea why  this one does  not follow the  naming convention
 * that  others obey.   It  seems to  him  that this  should  have been  called
 * `rb_enc_external_str_new`.
 */
VALUE rb_external_str_new_with_enc(const char *ptr, long len, rb_encoding *enc);

/**
 * Identical to rb_str_export(), except it additionally takes an encoding.
 *
 * @param[in]  obj            Target object.
 * @param[in]  enc            Target encoding.
 * @exception  rb_eTypeError  No implicit conversion to String.
 * @return     Converted ruby string of `enc` encoding.
 */
VALUE rb_str_export_to_enc(VALUE obj, rb_encoding *enc);

/**
 * Encoding conversion main routine.
 *
 * @param[in]  str   String to convert.
 * @param[in]  from  Source encoding.
 * @param[in]  to    Destination encoding.
 * @return     A copy of `str`, with conversion from `from` to `to` applied.
 * @note       `from` can be a null pointer.  `str`'s encoding is taken then.
 * @note       `to` can be a null pointer.  No-op then.
 */
VALUE rb_str_conv_enc(VALUE str, rb_encoding *from, rb_encoding *to);

/**
 * Identical  to rb_str_conv_enc(),  except  it additionally  takes IO  encoder
 * options.  The extra arguments  can be constructed using io_extract_modeenc()
 * etc.
 *
 * @param[in]  str      String to convert.
 * @param[in]  from     Source encoding.
 * @param[in]  to       Destination encoding.
 * @param[in]  ecflags  A set of enum ::ruby_econv_flag_type.
 * @param[in]  ecopts   Optional hash.
 * @return     A copy of `str`, with conversion from `from` to `to` applied.
 * @note       `from` can be a null pointer.  `str`'s encoding is taken then.
 * @note       `to` can be a null pointer.  No-op then.
 * @note       `ecopts` can be  ::RUBY_Qnil, which is equivalent  to passing an
 *             empty hash.
 */
VALUE rb_str_conv_enc_opts(VALUE str, rb_encoding *from, rb_encoding *to, int ecflags, VALUE ecopts);

/**
 * Scans the passed string to collect  its code range.  Because a Ruby's string
 * is mutable, its contents  change from time to time; so  does its code range.
 * A  long-lived string  tends  to fall  back to  ::RUBY_ENC_CODERANGE_UNKNOWN.
 * This API scans it and re-assigns a fine-grained code range constant.
 *
 * @param[out]  str  A string.
 * @return      An enum ::ruby_coderange_type.
 */
int rb_enc_str_coderange(VALUE str);

/**
 * Scans the passed string until it finds something odd.  Returns the number of
 * bytes scanned.  As the name implies this is suitable for repeated call.  One
 * of its application is `IO#readlines`.   The method reads from its receiver's
 * read buffer, maybe more than once,  looking for newlines.  But "newline" can
 * be different among encodings.  This API is used to detect broken contents to
 * properly mark them as such.
 *
 * @param[in]   str  String to scan.
 * @param[in]   end  End of `str`.
 * @param[in]   enc  `str`'s encoding.
 * @param[out]  cr   Return buffer.
 * @return      Distance between `str` and first such byte where broken.
 * @post        `cr` has the code range type.
 */
long rb_str_coderange_scan_restartable(const char *str, const char *end, rb_encoding *enc, int *cr);

/**
 * Queries if  the passed string  is "ASCII only".  An  ASCII only string  is a
 * string  who doesn't  have any  non-ASCII  characters at  all.  This  doesn't
 * necessarily mean the string is in  ASCII encoding.  For instance a String of
 * CP932 encoding can quite much be ASCII only, depending on its contents.
 *
 * @param[in]  str  String in question.
 * @retval     1    It doesn't have non-ASCII characters.
 * @retval     0    It has characters that are out of ASCII.
 */
int rb_enc_str_asciionly_p(VALUE str);

RBIMPL_ATTR_NONNULL(())
/**
 * Looks for the passed string in the passed buffer.
 *
 * @param[in]  x          Buffer that potentially includes `y`.
 * @param[in]  m          Number of bytes of `x`.
 * @param[in]  y          Query string.
 * @param[in]  n          Number of bytes of `y`.
 * @param[in]  enc        Encoding of both `x` and `y`.
 * @retval     -1         Not found.
 * @retval     otherwise  Found index in `x`.
 * @note       This API can match at a non-character-boundary.
 */
long rb_memsearch(const void *x, long m, const void *y, long n, rb_encoding *enc);

/** @cond INTERNAL_MACRO */
RBIMPL_ATTR_NONNULL(())
static inline VALUE
rbimpl_enc_str_new_cstr(const char *str, rb_encoding *enc)
{
    long len = rbimpl_strlen(str);

    return rb_enc_str_new_static(str, len, enc);
}

#define rb_enc_str_new(str, len, enc)           \
    ((RBIMPL_CONSTANT_P(str) &&                 \
      RBIMPL_CONSTANT_P(len) ?                  \
      rb_enc_str_new_static:                    \
      rb_enc_str_new) ((str), (len), (enc)))

#define rb_enc_str_new_cstr(str, enc)           \
    ((RBIMPL_CONSTANT_P(str)  ?                 \
      rbimpl_enc_str_new_cstr :                 \
      rb_enc_str_new_cstr) ((str), (enc)))

/** @endcond */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_STRING_H */
