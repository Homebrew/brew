#ifndef RBIMPL_INTERN_STRING_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_STRING_H
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
 * @brief      Public APIs related to ::rb_cString.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#endif

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/constant_p.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/variable.h" /* rb_gvar_setter_t */
#include "ruby/st.h"         /* st_index_t */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* string.c */

/**
 * Allocates an instance of ::rb_cString.
 *
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An  instance   of  ::rb_cString,  of  `len`   bytes  length,  of
 *             "binary" encoding, whose contents are verbatim copy of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 */
VALUE rb_str_new(const char *ptr, long len);

/**
 * Identical to rb_str_new(), except it assumes the passed pointer is a pointer
 * to a C string.
 *
 * @param[in]  ptr             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @exception  rb_eArgError    `ptr` is a null pointer.
 * @return     An  instance  of  ::rb_cString,   of  "binary"  encoding,  whose
 *             contents are verbatim copy of `ptr`.
 * @pre        `ptr` must not be a null pointer.
 */
VALUE rb_str_new_cstr(const char *ptr);

/**
 * Identical to rb_str_new_cstr(),  except it takes a Ruby's  string instead of
 * C's.  Implementation wise it creates a string that shares the backend memory
 * region with the receiver.   So the name.  But there is  no way for extension
 * libraries to know if a string is of such variant.
 *
 * @param[in]  str  An object of ::RString.
 * @return     An  allocated   instance  of  ::rb_cString,  which   shares  the
 *             encoding, length, and contents with the passed string.
 * @pre        `str` must not be any arbitrary object except ::RString.
 * @note       Use #StringValue to enforce the precondition.
 */
VALUE rb_str_new_shared(VALUE str);

/**
 * Creates  a frozen  copy of  the string,  if necessary.   This function  does
 * nothing when the passed string is already frozen.  Otherwise, it allocates a
 * copy of it, which is frozen.  The passed string is untouched either ways.
 *
 * @param[in]  str  An object of ::RString.
 * @return     Something frozen.
 * @pre        `str` must not be any arbitrary object except ::RString.
 * @note       Use #StringValue to enforce the precondition.
 */
VALUE rb_str_new_frozen(VALUE str);

/**
 * Identical  to rb_str_new(),  except it  takes  the class  of the  allocating
 * object.
 *
 * @param[in]  obj             A string-ish object.
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An instance  of the class  of `obj`,  of `len` bytes  length, of
 *             "binary" encoding, whose contents are verbatim copy of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 *
 * @internal
 *
 * Why it doesn't take an instance of ::rb_cClass?
 */
VALUE rb_str_new_with_class(VALUE obj, const char *ptr, long len);

/**
 * Identical  to  rb_str_new(),  except  it  generates  a  string  of  "default
 * external" encoding.
 *
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default internal"  to "default external" is  fully defined over
 *             the  given  contents, then  the  return  value  is a  string  of
 *             "default external"  encoding, whose  contents are  the converted
 *             ones.  Otherwise the string is a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 */
VALUE rb_external_str_new(const char *ptr, long len);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_external_str_new(), except it  assumes the passed pointer is
 * a pointer  to a C  string.  It can  also be seen  as a routine  identical to
 * rb_str_new_cstr(),  except  it  generates  a string  of  "default  external"
 * encoding.
 *
 * @param[in]  ptr             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default internal"  to "default external" is  fully defined over
 *             the  given  contents, then  the  return  value  is a  string  of
 *             "default external"  encoding, whose  contents are  the converted
 *             ones.  Otherwise the string is a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 * @pre        `ptr` must not be a null pointer.
 */
VALUE rb_external_str_new_cstr(const char *ptr);

/**
 * Identical  to  rb_str_new(),  except  it  generates  a  string  of  "locale"
 * encoding.    It   can   also   be   seen   as   a   routine   identical   to
 * rb_external_str_new(),  except it  generates a  string of  "locale" encoding
 * instead of "default external" encoding.
 *
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default internal" to  "locale" is fully defined  over the given
 *             contents,  then  the  return  value  is  a  string  of  "locale"
 *             encoding, whose contents are  the converted ones.  Otherwise the
 *             string is a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 */
VALUE rb_locale_str_new(const char *ptr, long len);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_locale_str_new(), except it  assumes the passed pointer is a
 * pointer  to a  C string.   It can  also be  seen as  a routine  identical to
 * rb_external_str_new_cstr(),  except  it  generates   a  string  of  "locale"
 * encoding instead of "default external".
 *
 * @param[in]  ptr             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default internal" to  "locale" is fully defined  over the given
 *             contents,  then  the  return  value  is  a  string  of  "locale"
 *             encoding, whose contents are  the converted ones.  Otherwise the
 *             string is a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 * @pre        `ptr` must not be a null pointer.
 */
VALUE rb_locale_str_new_cstr(const char *ptr);

/**
 * Identical  to rb_str_new(),  except it  generates a  string of  "filesystem"
 * encoding.    It   can   also   be   seen   as   a   routine   identical   to
 * rb_external_str_new(), except it generates a string of "filesystem" encoding
 * instead of "default external" encoding.
 *
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default  internal" to  "filesystem" is  fully defined  over the
 *             given  contents,   then  the  return   value  is  a   string  of
 *             "filesystem" encoding,  whose contents  are the  converted ones.
 *             Otherwise the string is a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 */
VALUE rb_filesystem_str_new(const char *ptr, long len);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to  rb_filesystem_str_new(), except it assumes  the passed pointer
 * is a pointer to  a C string.  It can also be seen  as a routine identical to
 * rb_external_str_new_cstr(),  except it  generates a  string of  "filesystem"
 * encoding instead of "default external".
 *
 * @param[in]  ptr             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default  internal" to  "filesystem" is  fully defined  over the
 *             given  contents,   then  the  return   value  is  a   string  of
 *             "filesystem" encoding,  whose contents  are the  converted ones.
 *             Otherwise the string is a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 * @pre        `ptr` must not be a null pointer.
 */
VALUE rb_filesystem_str_new_cstr(const char *ptr);

/**
 * Allocates  a "string  buffer".   A  string buffer  here  is  an instance  of
 * ::rb_cString, whose  capacity is bigger than  the length of it.   If you can
 * say  that a  string grows  to  a specific  amount  of bytes,  this could  be
 * effective than resizing a string over and over again and again.
 *
 * @param[in]  capa  Designed capacity of the generating string.
 * @return     An empty string, of "binary" encoding, whose capacity is `capa`.
 */
VALUE rb_str_buf_new(long capa);

RBIMPL_ATTR_NONNULL(())
/**
 * This is a rb_str_buf_new() + rb_str_buf_cat() combo.
 *
 * @param[in]  ptr             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An  instance  of  ::rb_cString,   of  "binary"  encoding,  whose
 *             contents are verbatim copy of `ptr`.
 * @pre        `ptr` must not be a null pointer.
 *
 * @internal
 *
 * This must be identical to rb_str_new_cstr(), except done in inefficient way?
 * @shyouhei doesn't understand why this is not a simple alias.
 */
VALUE rb_str_buf_new_cstr(const char *ptr);

/**
 * Allocates a  "temporary" string.  This is  a hidden empty string.   Handy on
 * occasions.
 *
 * @param[in]  len  Designed length of the string.
 * @return     A hidden, empty string.
 * @see        rb_obj_hide()
 */
VALUE rb_str_tmp_new(long len);

/**
 * Identical  to rb_str_new(),  except  it  generates a  string  of "US  ASCII"
 * encoding.  This  is different from  rb_external_str_new(), not only  for the
 * output encoding, but also it doesn't convert the contents.
 *
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An  instance   of  ::rb_cString,  of  `len`   bytes  length,  of
 *             "US ASCII" encoding, whose contents are verbatim copy of `ptr`.
 */
VALUE rb_usascii_str_new(const char *ptr, long len);

/**
 * Identical to rb_str_new_cstr(),  except it generates a string  of "US ASCII"
 * encoding.   It   can   also   be    seen   as   a   routine   Identical   to
 * rb_usascii_str_new(), except it assumes the passed pointer is a pointer to a
 * C string.
 *
 * @param[in]  ptr             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @exception  rb_eArgError    `ptr` is a null pointer.
 * @return     An  instance  of ::rb_cString,  of  "US  ASCII" encoding,  whose
 *             contents are verbatim copy of `ptr`.
 * @pre        `ptr` must not be a null pointer.
 */
VALUE rb_usascii_str_new_cstr(const char *ptr);

/**
 * Identical to rb_str_new(), except it generates a string of "UTF-8" encoding.
 *
 * @param[in]  ptr             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An  instance   of  ::rb_cString,  of  `len`   bytes  length,  of
 *             "UTF-8" encoding, whose contents are verbatim copy of `ptr`.
 */
VALUE rb_utf8_str_new(const char *ptr, long len);

/**
 * Identical  to rb_str_new_cstr(),  except it  generates a  string of  "UTF-8"
 * encoding.    It   can   also   be   seen   as   a   routine   Identical   to
 * rb_usascii_str_new(), except it assumes the passed pointer is a pointer to a
 * C string.
 *
 * @param[in]  ptr             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @exception  rb_eArgError    `ptr` is a null pointer.
 * @return     An instance of ::rb_cString, of "UTF-8" encoding, whose contents
 *             are verbatim copy of `ptr`.
 * @pre        `ptr` must not be a null pointer.
 */
VALUE rb_utf8_str_new_cstr(const char *ptr);

/**
 * @name Special strings that are backended by C string literals.
 *
 *  *_str_new_static functions are intended for C string literals.
 *  They require memory in the range [ptr, ptr+len] to always be readable.
 *  Note that this range covers a total of len + 1 bytes.
 *
 * @{
 */

/**
 * Identical to rb_str_new(), except it takes a C string literal.
 *
 * @param[in]  ptr           A C string literal.
 * @param[in]  len           `strlen(ptr)`.
 * @exception  rb_eArgError  `len` out of range of `size_t`.
 * @pre        `ptr` must be a C string constant.
 * @return     An instance of ::rb_cString, of "binary" encoding, whose backend
 *             storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 *
 * @internal
 *
 * Surprisingly it can take NULL, and generates an empty string.
 */
VALUE rb_str_new_static(const char *ptr, long len);

/**
 * Identical to rb_str_new_static(), except it generates a string of "US ASCII"
 * encoding instead of "binary".  It can also be seen as a routine identical to
 * rb_usascii_str_new(), except it takes a C string literal.
 *
 * @param[in]  ptr           A C string literal.
 * @param[in]  len           `strlen(ptr)`.
 * @exception  rb_eArgError  `len` out of range of `size_t`.
 * @pre        `ptr` must be a C string constant.
 * @return     An  instance  of ::rb_cString,  of  "US  ASCII" encoding,  whose
 *             backend storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 */
VALUE rb_usascii_str_new_static(const char *ptr, long len);

/**
 * Identical to  rb_str_new_static(), except it  generates a string  of "UTF-8"
 * encoding instead of "binary".  It can also be seen as a routine identical to
 * rb_utf8_str_new(), except it takes a C string literal.
 *
 * @param[in]  ptr           A C string literal.
 * @param[in]  len           `strlen(ptr)`.
 * @exception  rb_eArgError  `len` out of range of `size_t`.
 * @pre        `ptr` must be a C string constant.
 * @return     An instance of ::rb_cString,  of "UTF-8" encoding, whose backend
 *             storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 */
VALUE rb_utf8_str_new_static(const char *ptr, long len);

/** @} */

/**
 * Identical to rb_interned_str(),  except it takes a Ruby's  string instead of
 * C's.  It can also be seen  as a routine identical to to rb_str_new_shared(),
 * except it returns an infamous "f"string.
 *
 * @param[in]  str  An object of ::RString.
 * @return     An instance  of ::rb_cString, either cached  or allocated, which
 *             has the identical encoding, length, and contents with the passed
 *             string.
 * @pre        `str` must not be any arbitrary object except ::RString.
 * @note       Use #StringValue to enforce the precondition.
 *
 * @internal
 *
 * It  actually  finds  or  creates  a fstring  of  the  needed  property,  and
 * destructively modifies  the receiver behind-the-scene  so that it  becomes a
 * shared string whose parent is the returning fstring.
 */
VALUE rb_str_to_interned_str(VALUE str);

/**
 * Identical to rb_str_new(), except it returns an infamous "f"string.  What is
 * a  fstring?  Well  it is  a special  subkind of  strings that  is immutable,
 * deduped globally, and managed by our GC.   It is much like a Symbol (in fact
 * Symbols  are dynamic  these days  and are  backended using  fstrings).  This
 * concept has been  silently introduced at some point in  2.x era.  Since then
 * it  gained  wider acceptance  in  the  core.   Starting from  3.x  extension
 * libraries can also generate ones.
 *
 * @param[in]  ptr           A memory region of `len` bytes length.
 * @param[in]  len           Length  of  `ptr`,  in bytes,  not  including  the
 *                           terminating NUL character.
 * @exception  rb_eArgError  `len` is negative.
 * @return     A  found or  created instance  of ::rb_cString,  of `len`  bytes
 *             length, of  "binary" encoding,  whose contents are  identical to
 *             that of `ptr`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 */
VALUE rb_interned_str(const char *ptr, long len);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to  rb_interned_str(), except it  assumes the passed pointer  is a
 * pointer to a C's  string.  It can also be seen as a  routine identical to to
 * rb_str_to_interned_str(), except  it takes a  C's string instead  of Ruby's.
 * Or it can  also be seen as a routine  identical to rb_str_new_cstr(), except
 * it returns an infamous "f"string.
 *
 * @param[in]  ptr             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An  instance  of  ::rb_cString,   of  "binary"  encoding,  whose
 *             contents are verbatim copy of `ptr`.
 * @pre        `ptr` must not be a null pointer.
 */
VALUE rb_interned_str_cstr(const char *ptr);

/**
 * Destroys the given string for no reason.
 *
 * @warning  DO NOT USE IT.
 * @warning  Leave this task to our GC.
 * @warning  It was a bad idea at the first place to let you know about it.
 *
 * @param[out]  str  The string to be executed.
 * @post        The given string no longer exists.
 * @note        Maybe `String#clear` could be what you want.
 *
 * @internal
 *
 * Should have moved this to `internal/string.h`.
 */
void rb_str_free(VALUE str);

/**
 * Replaces the contents of the former with the latter.
 *
 * @param[out]  dst  Destination object.
 * @param[in]   src  Source object.
 * @pre         Both  objects   must  not  be  any   arbitrary  objects  except
 *              ::RString.
 * @post        `dst`'s  former  components  are  abandoned.  It  now  has  the
 *              identical encoding, length, and contents to `src`.
 * @see         rb_str_replace()
 *
 * @internal
 *
 * @shyouhei  doesn't understand  why this  is useful  to extension  libraries.
 * Just use rb_str_replace().  What's wrong with that?
 */
void rb_str_shared_replace(VALUE dst, VALUE src);

/**
 * Identical to  rb_str_cat_cstr(), except  it takes  Ruby's string  instead of
 * C's.  It can also be seen as a routine identical to rb_str_shared_replace(),
 * except it appends instead of replaces.
 *
 * @param[out]  dst                 Destination object.
 * @param[in]   src                 Source object.
 * @exception   rb_eEncCompatError  Can't mix the encodings.
 * @exception   rb_eArgError        Result string too big.
 * @return      The passed `dst`.
 * @pre         Both  objects   must  not  be  any   arbitrary  objects  except
 *              ::RString.
 * @post        `dst`  has  the  contents  of  `src`  appended,  with  encoding
 *              converted into `dst`'s one, into the end of `dst`.
 */
VALUE rb_str_buf_append(VALUE dst, VALUE src);

/** @alias{rb_str_cat} */
VALUE rb_str_buf_cat(VALUE, const char*, long);

/** @alias{rb_str_cat_cstr} */
VALUE rb_str_buf_cat2(VALUE, const char*);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to  rb_str_cat_cstr(), except  it additionally assumes  the source
 * string be a NUL terminated ASCII string.
 *
 * @param[out]  dst           Destination object.
 * @param[in]   src           Source string.
 * @exception   rb_eArgError  Result string too big.
 * @return      The passed `dst`.
 * @pre         `dst` must not be any arbitrary object except ::RString.
 * @pre         `src` must be a NUL terminated ASCII string.
 * @post        `dst`  has  the  contents  of  `src`  appended,  with  encoding
 *              converted into `dst`'s one, into the end of `dst`.
 */
VALUE rb_str_buf_cat_ascii(VALUE dst, const char *src);

/**
 * Try converting an  object to its stringised representation  using its `to_s`
 * method, if  any.  If  there is  no such thing,  it resorts  to rb_any_to_s()
 * output.
 *
 * @param[in]  obj  Arbitrary ruby object to stringise.
 * @return     An instance of ::rb_cString.
 */
VALUE rb_obj_as_string(VALUE obj);

/**
 * Try converting an object to its stringised representation using its `to_str`
 * method, if any.  If there is no such thing, returns ::RUBY_Qnil.
 *
 * @param[in]  obj            Arbitrary ruby object to stringise.
 * @exception  rb_eTypeError  `obj.to_str` returned something non-String.
 * @retval     RUBY_Qnil      No conversion from obj to String defined.
 * @return     otherwise      Stringised representation of `obj`.
 * @see        rb_io_check_io
 * @see        rb_check_array_type
 * @see        rb_check_hash_type
 */
VALUE rb_check_string_type(VALUE obj);

/**
 * Asserts that  the given  string's encoding is  (Ruby's definition  of) ASCII
 * compatible.
 *
 * @param[in]  obj                 An instance of ::rb_cString.
 * @exception  rb_eEncCompatError  `obj` is ASCII incompatible.
 *
 * @internal
 *
 * @shyouhei doesn't know if this is an  Easter egg or an official feature, but
 * this function  can in fact take  non-strings such as Symbols,  Regexps, IOs,
 * etc.  However if something unsupported is  passed, it causes SEGV.  It seems
 * the feature is kind of untested.
 */
void rb_must_asciicompat(VALUE obj);

/**
 * Duplicates a string.
 *
 * @param[in]  str  String in question to duplicate.
 * @return     A duplicated new instance.
 * @pre        `str` must be of ::RString.
 */
VALUE rb_str_dup(VALUE str);

/**
 * I guess there  is no use case  of this function in  extension libraries, but
 * this is  a routine identical  to rb_str_dup(),  except it always  creates an
 * instance of ::rb_cString regardless of the given object's class.  This makes
 * the most sense when the passed string is formerly hidden by rb_obj_hide().
 *
 * @param[in]  str  A string, possibly hidden.
 * @return     A duplicated new instance of ::rb_cString.
 */
VALUE rb_str_resurrect(VALUE str);

/**
 * Obtains a "temporary  lock" of the string.  This  advisory locking mechanism
 * prevents other  cooperating threads from  tampering the receiver.   The same
 * thing could be done via freeze mechanism,  but this one can also be unlocked
 * using rb_str_unlocktmp().
 *
 * @param[out]  str               String to lock.
 * @exception   rb_eRuntimeError  `str` already locked.
 * @return      The given string.
 * @post        The string is locked.
 */
VALUE rb_str_locktmp(VALUE str);

/**
 * Releases a lock formerly obtained by rb_str_locktmp().
 *
 * @param[out]  str               String to unlock.
 * @exception   rb_eRuntimeError  `str` already unlocked.
 * @return      The given string.
 * @post        The string is locked.
 */
VALUE rb_str_unlocktmp(VALUE str);

/** @alias{rb_str_new_frozen} */
VALUE rb_str_dup_frozen(VALUE);

/** @alias{rb_str_new_frozen} */
#define rb_str_dup_frozen rb_str_new_frozen

/**
 * Generates a new string, concatenating the former to the latter.  It can also
 * be seen as a routine identical  to rb_str_append(), except it doesn't tamper
 * the passed strings to create a new one instead.
 *
 * @param[in]  lhs                 Source string #1.
 * @param[in]  rhs                 Source string #2.
 * @exception  rb_eEncCompatError  Can't mix the encodings.
 * @exception  rb_eArgError        Result string too big.
 * @return     A new string containing `rhs` concatenated to `lhs`.
 * @pre        Both objects must not be any arbitrary objects except ::RString.
 * @note       This  operation  doesn't commute.   Don't  get  confused by  the
 *             "plus"  terminology.   For  historical reasons  there  are  some
 *             noncommutative `+`s in Ruby.  This is one of such things.  There
 *             has been a long discussion around `+`s in programming languages.
 */
VALUE rb_str_plus(VALUE lhs, VALUE rhs);

/**
 * Repetition of a string.
 *
 * @param[in]  str           String to repeat.
 * @param[in]  num           Count, something numeric.
 * @exception  rb_eArgError  `num` is negative.
 * @return     A new string repeating `num` times of `str`.
 */
VALUE rb_str_times(VALUE str, VALUE num);

/**
 * Byte  offset to  character offset  conversion.   This makes  sense when  the
 * receiver is in  a multibyte encoding.  The string's i-th  character does not
 * always sit at its  i-th byte.  This function scans the  contents to find the
 * character index that matches the byte  index.  Generally speaking this is an
 * `O(n)` operation.  Could be slow.
 *
 * @param[in]  str  The string to scan.
 * @param[in]  pos  Offset, in bytes.
 * @return     Offset, in characters.
 */
long rb_str_sublen(VALUE str, long pos);

/**
 * This is the implementation of two-argumented `String#slice`.
 *
 * - Returns the substring of the given `len` found in `str` at offset `beg`:
 *
 *   ```ruby
 *   'foo'[0, 2] # => "fo"
 *   'foo'[0, 0] # => ""
 *   ```
 *
 * - Counts backward from the end of `str` if `beg` is negative:
 *
 *   ```ruby
 *   'foo'[-2, 2] # => "oo"
 *   ```
 *
 * - Special case: returns a  new empty string if `beg` is  equal to the length
 *   of `str`:
 *
 *   ```ruby
 *   'foo'[3, 2] # => ""
 *   ```
 *
 * - Returns a null pointer if `beg` is out of range:
 *
 *   ```ruby
 *   'foo'[4, 2] # => nil
 *   'foo'[-4, 2] # => nil
 *   ```
 *
 * - Returns the trailing substring of `str` if `len` is large:
 *
 *   ```ruby
 *   'foo'[1, 50] # => "oo"
 *   ```
 *
 * - Returns a null pointer if `len` is negative:
 *
 *   ```ruby
 *   'foo'[0, -1] # => nil
 *   ```
 *
 * @param[in]  str        The string to slice.
 * @param[in]  beg        Requested offset of the substring.
 * @param[in]  len        Requested length of the substring.
 * @retval     RUBY_Qnil  Parameters out of range.
 * @retval     otherwise  A  new   string  whose  contents  is   the  specified
 *                        substring of `str`.
 * @pre        `str` must not be any arbitrary objects except ::RString.
 */
VALUE rb_str_substr(VALUE str, long beg, long len);

/**
 * Identical to  rb_str_substr(), except  the numbers  are interpreted  as byte
 * offsets instead of character offsets.
 *
 * @param[in]  str  The string to slice.
 * @param[in]  beg  Requested offset of the substring.
 * @param[in]  len  Requested length of the substring.
 * @return     A new string whose contents is the specified substring of `str`.
 * @pre        `str` must not be any arbitrary objects except ::RString.
 * @pre        `beg` and `len` must not point to OOB contents.
 */
VALUE rb_str_subseq(VALUE str, long beg, long len);

/**
 * Identical  to rb_str_substr(),  except it  returns a  C's string  instead of
 * Ruby's.
 *
 * @param[in]      str        The string to slice.
 * @param[in]      beg        Requested offset of the substring.
 * @param[in,out]  len        Requested length of the substring.
 * @retval         NULL       Parameters out of range.
 * @retval         otherwise  A pointer inside of `str`'s backend storage where
 *                            the specified substring exist.
 * @pre            `str` must not be any arbitrary objects except ::RString.
 * @post           `len` is updated to have the length of the return value.
 */
char *rb_str_subpos(VALUE str, long beg, long *len);

/**
 * Declares that the string is about to be modified.  This for instance let the
 * string have a dedicated backend storage.
 *
 * @param[out]  str               String about to be modified.
 * @exception   rb_eRuntimeError  `str` is `locktmp`-ed.
 * @exception   rb_eFrozenError   `str` is frozen.
 * @pre         `str` must not be any arbitrary objects except ::RString.
 * @post        Upon  successful return  the passed  string is  eligible to  be
 *              modified.
 */
void rb_str_modify(VALUE str);

/**
 * Identical to rb_str_modify(), except it additionally expands the capacity of
 * the receiver.
 *
 * @param[out]  str               Target string to modify.
 * @param[in]   capa              Additional capacity to add.
 * @exception   rb_eArgError      `capa` is negative.
 * @exception   rb_eRuntimeError  `str` is `locktmp`-ed.
 * @exception   rb_eFrozenError   `str` is frozen.
 * @pre         `str` must not be any arbitrary objects except ::RString.
 * @post        Upon successful  return the passed  string is modified  so that
 *              its capacity is increased for `capa` bytes.
 */
void rb_str_modify_expand(VALUE str, long capa);

/**
 * This is the implementation of `String#freeze`.
 *
 * @param[out]  str  Target string to freeze.
 * @return      The passed string.
 * @post        Upon successful return the passed string is frozen.
 */
VALUE rb_str_freeze(VALUE str);

/**
 * Overwrites the  length of the  string.  Typically this  is used to  shrink a
 * string that was formerly expanded.
 *
 * ```CXX
 * extern int fd;
 * auto str = rb_eval_string("'...'");
 * rb_str_modify_expand(str, BUFSIZ);
 * if (auto len = recv(fd, RSTRING_PTR(str), BUFSIZ, 0); len >= 0) {
 *     rb_str_set_len(str, len);
 * }
 * else {
 *     rb_sys_fail("recv(2)");
 * }
 * ```
 *
 * @param[out]  str               String to shrink.
 * @param[in]   len               New length of the string.
 * @exception   rb_eRuntimeError  `str` is `locktmp`-ed.
 * @exception   rb_eFrozenError   `str` is frozen.
 * @pre         `str` must not be any arbitrary objects except ::RString.
 * @post        Upon successful return `str`'s length is set to `len`.
 */
void rb_str_set_len(VALUE str, long len);

/**
 * Overwrites the length of the  string.  In contrast to rb_str_set_len(), this
 * function can also expand a string.
 *
 * @param[out]  str               String to shrink.
 * @param[in]   len               New length of the string.
 * @exception   rb_eArgError      `len` is negative.
 * @exception   rb_eRuntimeError  `str` is `locktmp`-ed.
 * @exception   rb_eFrozenError   `str` is frozen.
 * @return      The passed `str`.
 * @pre         `str` must not be any arbitrary objects except ::RString.
 * @post        Upon successful return `str` is  either expanded or shrunken to
 *              have its length be `len`.
 */
VALUE rb_str_resize(VALUE str, long len);

/**
 * Destructively appends the passed contents to the string.
 *
 * @param[out]  dst           Destination object.
 * @param[in]   src           Contents to append.
 * @param[in]   srclen        Length of `src`.
 * @exception   rb_eArgError  `srclen` is negative.
 * @return      The passed `dst`.
 * @pre         `dst` must not be any arbitrary objects except ::RString.
 * @post        `dst` has the contents of `ptr` appended.
 */
VALUE rb_str_cat(VALUE dst, const char *src, long srclen);

/**
 * Identical to rb_str_cat(), except it assumes the passed pointer is a pointer
 * to a C string.
 *
 * @param[out]  dst           Destination object.
 * @param[in]   src           Contents to append.
 * @exception   rb_eArgError  Result string too big.
 * @exception   rb_eArgError  `src` is a null pointer.
 * @return      The passed `dst`.
 * @pre         `dst` must not be any arbitrary objects except ::RString.
 * @pre         `src` must not be a null pointer.
 * @post        `dst` has the contents of `src` appended.
 */
VALUE rb_str_cat_cstr(VALUE dst, const char *src);

/** @alias{rb_str_cat_cstr} */
VALUE rb_str_cat2(VALUE, const char*);

/**
 * Identical to  rb_str_buf_append(), except  it converts  the right  hand side
 * before concatenating.
 *
 * @param[out]  dst                 Destination object.
 * @param[in]   src                 Source object.
 * @exception   rb_eEncCompatError  Can't mix the encodings.
 * @exception   rb_eArgError        Result string too big.
 * @return      The passed `dst`.
 * @pre         `dst` must not be any arbitrary objects except ::RString.
 * @post        `dst`  has  the  contents  of  `src`  appended,  with  encoding
 *              converted into `dst`'s one, into the end of `dst`.
 */
VALUE rb_str_append(VALUE dst, VALUE src);

/**
 * Identical  to  rb_str_append(), except  it  also  accepts  an integer  as  a
 * codepoint.  This resembles `String#<<`.
 *
 * @param[out]  dst                 Destination object.
 * @param[in]   src                 Source object, String or Numeric.
 * @exception   rb_eRangeError      Source numeric is out of range.
 * @exception   rb_eEncCompatError  Source string too long.
 * @exception   rb_eArgError        Result string too big.
 * @return      The passed `dst`.
 * @pre         `dst` must not be any arbitrary objects except ::RString.
 * @post        `dst`  has  the  contents  of  `src`  appended,  with  encoding
 *              converted into `dst`'s one, into the end of `dst`.
 */
VALUE rb_str_concat(VALUE dst, VALUE src);

/* random.c */

/**
 * This is a universal hash function.
 *
 * @warning    This function changes its value per process.
 * @param[in]  ptr  Target message.
 * @param[in]  len  Length of `ptr` in bytes.
 * @return     A pseudorandom number suitable for Hash's hash value.
 * @see        Aumasson,  JP., Bernstein,  D.J., "SipHash:  A Fast  Short-Input
 *             PRF",  In  proceedings  of   13th  International  Conference  on
 *             Cryptology in  India (INDOCRYPT 2012), LNCS  7668, pp.  489-508,
 *             2012.  http://doi.org/10.1007/978-3-642-34931-7_28
*/
st_index_t rb_memhash(const void *ptr, long len);

/**
 * Starts a series of hashing.  Suppose you have a struct:
 *
 * ```CXX
 * struct foo_tag {
 *     unsigned char bar;
 *     uint32_t baz;
 * };
 * ```
 *
 * It is not a  wise idea to call rb_memhash() over it,  because there could be
 * padding bits.  Instead you should explicitly iterate over each fields:
 *
 * ```CXX
 * foo_tag foo = { 0, 0, };
 * st_index_t hash = 0;
 *
 * hash = rb_hash_start(0);
 * hash = rb_hash_uint(hash, foo.bar);
 * hash = rb_hash_uint32(hash, foo.baz);
 * hash = rb_hash_end(hash);
 * ```
 *
 * @param[in]  i  Initial value.
 * @return     A hash value.
 */
st_index_t rb_hash_start(st_index_t i);

/** @alias{st_hash_uint32} */
#define rb_hash_uint32(h, i) st_hash_uint32((h), (i))

/** @alias{st_hash_uint} */
#define rb_hash_uint(h, i) st_hash_uint((h), (i))

/** @alias{st_hash_end} */
#define rb_hash_end(h) st_hash_end(h)

/* string.c */

/**
 * Calculates a hash value of a string.   This is one of the two functions that
 * constructs struct ::st_hash_type.
 *
 * @param[in]  str  An object of ::RString.
 * @return     A hash value.
 * @pre        `str` must not be any arbitrary object except ::RString.
 *
 * @internal
 *
 * Although safe to call, there must be no particular use case of this function
 * for extension libraries.  Only ruby internals must know about it.
 *
 * This is not a simple alias  of rb_memhash(), because it considers the passed
 * string's encoding as well as its contents.
 */
st_index_t rb_str_hash(VALUE str);

/**
 * Compares two  strings.  This  is one  of the  two functions  that constructs
 * struct ::st_hash_type.
 *
 * @param[in]  str1  A string.
 * @param[in]  str2  Another string.
 * @retval     1     They have identical contents, length, and encodings.
 * @retval     0     Otherwise.
 * @pre        Both   objects   must  not  be  any   arbitrary  objects  except
 *             ::RString.
 *
 * @internal
 *
 * In contrast to  rb_str_hash(), this could be handy for  comparison that only
 * concerns equality.  rb_str_cmp() returns 1, 0, -1.
 */
int rb_str_hash_cmp(VALUE str1, VALUE str2);

/**
 * Checks  if  two   strings  are  comparable  each  other   or  not.   Because
 * rb_str_cmp()  must  return  "lesser  than" or  "greater  than"  information,
 * comparing two strings needs a stricter restriction.  Both sides must be in a
 * same set of strings which have total order.  This is to check that property.
 * Intuitive it  sounds?  But they  can have different encodings.   A character
 * and another might or might not appear in the same order in their codepoints.
 * It is complicated than you think.
 *
 * @param[in]  str1  A string.
 * @param[in]  str2  Another string.
 * @retval     1     They agree on a total order.
 * @retval     0     Otherwise.
 * @pre        Both   objects   must  not  be  any   arbitrary  objects  except
 *             ::RString.
 */
int rb_str_comparable(VALUE str1, VALUE str2);

/**
 * Compares two strings, as in `strcmp(3)`.  This does not consider the current
 * locale, but considers the encodings of both sides instead.
 *
 * @param[in]  lhs  A string.
 * @param[in]  rhs  Another string.
 * @retval     -1   `lhs` is "bigger than" `rhs`.
 * @retval      1   `rhs` is "bigger than" `lhs`.
 * @retval      0    Otherwise, e.g. not comparable.
 * @pre        Both   objects   must  not  be  any   arbitrary  objects  except
 *             ::RString.
 */
int rb_str_cmp(VALUE lhs, VALUE rhs);

/**
 * Equality of two strings.
 *
 * If `str2` is not a String, it  resorts to `str2 == str1`.  Otherwise if they
 * are not comparable, returns ::RUBY_Qfalse.   Otherwise if they have the same
 * contents  and   the  length,   returns  ::RUBY_Qtrue.    Otherwise,  returns
 * ::RUBY_Qfalse.
 *
 * @param[in]  str1         A string.
 * @param[in]  str2         Another string.
 * @retval     RUBY_Qtrue   They are equal.
 * @retval     RUBY_Qfalse  They are either different, or not comparable.
 */
VALUE rb_str_equal(VALUE str1, VALUE str2);

/**
 * Shrinks the given string for the given number of bytes.
 *
 * @param[out]  str               String to squash.
 * @param[in]   len               Number of bytes to reduce.
 * @exception   rb_eRuntimeError  `str` is `locktmp`-ed.
 * @exception   rb_eFrozenError   `str` is frozen.
 * @return      The passed `str`.
 * @pre         `str` must not be any arbitrary objects except ::RString.
 * @post        `str` is shrunken.
 * @warning     Can break a multibyte character in middle.
 *
 * @internal
 *
 * What if `len` is negative?
 */
VALUE rb_str_drop_bytes(VALUE str, long len);

/**
 * Replaces some  (or all) of  the contents of the  given string.  This  is the
 * implementation of three-argumented `String#[]=`.
 *
 * @param[out]  dst               Target string to update.
 * @param[in]   beg               Offset of the affected portion.
 * @param[in]   len               Length of the affected portion.
 * @param[in]   src               Object to be assigned.
 * @exception   rb_eTypeError     `src` has no implicit conversion to String.
 * @exception   rb_eIndexError    `len` is negative, or `beg` is OOB.
 * @exception   rb_eRuntimeError  `dst` is `locktmp`-ed.
 * @exception   rb_eFrozenError   `dst` is frozen.
 * @note        Unlike rb_str_substr(), this function raises.
 * @post        A  portion of  `dst`  from  `beg` to  `len`  is the  stringised
 *              representation of `src`.  If that replacement string is not the
 *              same  length as  the portion  it  is replacing,  `dst` will  be
 *              resized accordingly.
 */
void rb_str_update(VALUE dst, long beg, long len, VALUE src);

/**
 * Replaces the contents  of the former object with the  stringised contents of
 * the latter.
 *
 * @param[out]  dst               Destination object.
 * @param[in]   src               Source object.
 * @exception   rb_eTypeError     `src` has no implicit conversion to String.
 * @exception   rb_eRuntimeError  `dst` is `locktmp`-ed.
 * @exception   rb_eFrozenError   `dst` is frozen.
 * @return      The passed `dst`.
 * @pre        `dst` must not be any arbitrary object except ::RString.
 * @post        `dst`'s  former  components  are  abandoned.  It  now  has  the
 *              identical encoding, length, and contents to `src`.
 */
VALUE rb_str_replace(VALUE dst, VALUE src);

/**
 * Generates a "readable" version of the receiver.
 *
 * @warning    The output is _insecure_.  Never feed one to `eval`.
 * @warning    The output is not always in the same encoding as the given one.
 * @warning    A  character might  or might  not be  escaped, depending  on the
 *             result encoding.
 * @param[in]  str  String to inspect.
 * @return     Its inspection, either  in default internal encoding  if any, or
 *             in default external encoding otherwise.
 * @see        rb_str_dump()
 *
 * @internal
 *
 * This is a  (silent) fix of an actual vulnerability  feeding `inspect` output
 * strings to `eval`:
 * https://github.com/hiki/hiki/commit/8771a6e25198e264a2bf9dc1c102fea2cc8ff975
 *
 * ... and its advisory:
 * http://hikiwiki.org/en/advisory20040712.html
 */
VALUE rb_str_inspect(VALUE str);

/**
 * "Inverse" of rb_eval_string().  Returns a quoted version of the string.  All
 * non-printing characters are replaced by  `\uNNNN` or `\xHH` notation and all
 * special characters are escaped.  The result string is guaranteed to render a
 * string of the same contents when passed to `eval` and friends.
 *
 * @param[in]  str               String to dump.
 * @exception  rb_eRuntimeError  Too  many  escape   sequences  causes  integer
 *                               overflow on the length of the string.
 * @return     An  US-ASCII string  that  includes all  the  necessary info  to
 *             reconstruct the original string.
 */
VALUE rb_str_dump(VALUE str);

/**
 * Divides  the  given string  based  on  the  given  delimiter.  This  is  the
 * 1-argument 0-block version of `String#split`.
 *
 * @param[in]  str            Object in question to split.
 * @param[in]  delim          Delimiter, in C string.
 * @exception  rb_eTypeError  `str` has no implicit conversion to String.
 * @exception  rb_eArgError   `delim` is a null pointer.
 * @return     An array of  strings, which are substrings of  the passed `str`.
 *             If `delim` is an empty C string (i.e. `""`), `str` is split into
 *             each characters.  If `delim` is a C string whose sole content is
 *             a whitespace (i.e.  `" "`), `str` is split  on whitespaces, with
 *             leading  and   trailing  whitespace   and  runs   of  contiguous
 *             whitespace  characters  ignored.    Otherwise,  `str`  is  split
 *             according to `delim`.
 */
VALUE rb_str_split(VALUE str, const char *delim);

/**
 * This is a ::rb_gvar_setter_t that refutes non-string assignments.
 *
 * @exception  rb_eTypeError  Passed something non-string.
 */
rb_gvar_setter_t rb_str_setter;

/* symbol.c */

/**
 * Identical  to  rb_to_symbol(),  except  it assumes  the  receiver  being  an
 * instance of ::RString.
 *
 * @param[in]  str               The name of the id.
 * @exception  rb_eRuntimeError  Too many symbols.
 * @return     A (possibly new) id whose value is the given `str`.
 * @pre        `str` must not be any arbitrary object except ::RString.
 * @note       These   days  Ruby   internally   has  two   kinds  of   symbols
 *             (static/dynamic).   Symbols created  using  this function  would
 *             become dynamic ones; i.e. would  be garbage collected.  It could
 *             be safer for you to use it than alternatives, when applicable.
 */
VALUE rb_str_intern(VALUE str);

/* string.c */

/**
 * This is an rb_sym2str() + rb_str_dup() combo.
 *
 * @param[in]  sym  A symbol to query.
 * @return     A string duplicating the symbol's backend storage.
 *
 * @internal
 *
 * This function  causes SEGV  when the  passed value is  a static  symbol that
 * doesn't exist.
 */
VALUE rb_sym_to_s(VALUE sym);

/**
 * Counts the  number of characters (not  bytes) that are stored  inside of the
 * given string.  This  of course depends on its encoding.   Also this function
 * generally runs  in O(n), because  for instance you  have to scan  the entire
 * string to know how many characters are there in a UTF-8 string.
 *
 * @param[in]  str  Target string to query.
 * @return     Its number of characters.
 */
long rb_str_strlen(VALUE str);

/**
 * Identical to rb_str_strlen(), except it returns the value in ::rb_cInteger.
 *
 * @param[in]  str  Target string to query.
 * @return     Its number of characters.
 */
VALUE rb_str_length(VALUE);

/**
 * "Inverse" of rb_str_sublen().  This function  scans the contents to find the
 * byte index that matches the character  index.  Generally speaking this is an
 * `O(n)` operation.  Could be slow.
 *
 * @param[in]  str  The string to scan.
 * @param[in]  pos  Offset, in characters.
 * @return     Offset, in bytes.
 */
long rb_str_offset(VALUE str, long pos);

RBIMPL_ATTR_PURE()
/**
 * Queries the capacity of the given string.
 *
 * @see        ::RString::capa
 * @param[in]  str  String in question.
 * @return     Its capacity.
 */
size_t rb_str_capacity(VALUE str);

/**
 * Shortens `str` and adds three dots, an  ellipsis, if it is longer than `len`
 * characters.  The length of the returned string in characters is less than or
 * equal to `len`.  If the length of `str` is less than or equal `len`, returns
 * `str` itself.   The encoding of returned  string is equal to  that of passed
 * one.  The class of returned string is equal to that of passed one.
 *
 * @param[in]  str             The string to shorten.
 * @param[in]  len             The maximum string length.
 * @exception  rb_eIndexError  `len` is negative.
 * @retval     str             No need to add ellipsis.
 * @retval     otherwise       A new, shortened string.
 * @note       The length is counted in characters.
 */
VALUE rb_str_ellipsize(VALUE str, long len);

/**
 * "Cleanses" the string.   A string has its encoding and  its contents.  They,
 * in practice,  do not  always fit.  There  are strings in  the wild  that are
 * "broken"; include bit  patterns that are not allowed by  its encoding.  That
 * can  happen  when  a  user  copy&pasted something  bad,  network  input  got
 * clobbered by a middleman, cosmic rays hit the physical memory, and many more
 * occasions.  This function takes such strings, and fills the "broken" portion
 * with the passed replacement bit pattern.
 *
 * This function also takes a ruby block.  That is a neat way to do things, but
 * can be  annoying when the  caller function want to  use a block  for another
 * purpose.
 *
 * @param[in]  str                 Target string to scrub.
 * @param[in]  repl                Replacement  string.  When  it is  a string,
 *                                 this function  takes that as  a replacement.
 *                                 When it is  ::RUBY_Qnil, this function tries
 *                                 to  yield a  block  (if any)  and takes  its
 *                                 evaluated value  as a replacement.   In case
 *                                 of   ::RUBY_Qnil  without   a  block,   this
 *                                 function takes  an encoding-specific default
 *                                 character (`U+FFFD`, for instance) as a last
 *                                 resort.
 * @exception  rb_eTypeError       `repl` is neither string nor nil.
 * @exception  rb_eArgError        `repl` itself is broken.
 * @exception  rb_eEncCompatError  `repl` and `str` are incompatible.
 * @retval     RUBY_Qnil           `str` is already clean.
 * @retval     otherwise           A new, clean string.
 */
VALUE rb_str_scrub(VALUE str, VALUE repl);

/**
 * Searches for  the "successor"  of a string.   This function  is complicated!
 * This is  the only function in  the entire ruby  API (either C or  Ruby) that
 * generates a string out of thin air.  First, the successor to an empty string
 * is a new empty string:
 *
 * ```ruby
 * ''.succ # => ""
 * ```
 *
 * Otherwise  the successor  is  calculated by  "incrementing" characters.  The
 * first character to  be incremented is the rightmost alphanumeric:  or, if no
 * alphanumerics, the rightmost character:
 *
 * ```ruby
 * 'THX1138'.succ # => "THX1139"
 * '<<koala>>'.succ # => "<<koalb>>"
 * '***'.succ # => '**+'
 * ```
 *
 * The  successor to  a digit  is another  digit, "carrying"  to the  next-left
 * character for  a "rollover"  from 9  to 0, and  prepending another  digit if
 * necessary:
 *
 * ```ruby
 * '00'.succ # => "01"
 * '09'.succ # => "10"
 * '99'.succ # => "100"
 * '-9'.succ # => "-10"
 * ```
 *
 * The successor to  a letter is another  letter of the same  case, carrying to
 * the next-left  character for  a rollover,  and prepending  another same-case
 * letter if necessary:
 *
 * ```ruby
 * 'aa'.succ # => "ab"
 * 'az'.succ # => "ba"
 * 'zz'.succ # => "aaa"
 * 'AA'.succ # => "AB"
 * 'AZ'.succ # => "BA"
 * 'ZZ'.succ # => "AAA"
 * ```
 *
 * The successor to  a non-alphanumeric character is the next  character in the
 * underlying  character set's  collating sequence,  carrying to  the next-left
 * character for a rollover, and prepending another character if necessary:
 *
 * ```ruby
 * s = "\u03A1"
 * s.succ # => "\u03A3"  # There is no such thing like \u03A2.
 * s = 255.chr * 3
 * s # => "\xFF\xFF\xFF"
 * s.succ # => "\x01\x00\x00\x00"
 * ```
 *
 * Carrying can occur between and among mixtures of alphanumeric characters:
 *
 * ```ruby
 * s = 'zz99zz99'
 * s.succ # => "aaa00aa00"
 * s = '99zz99zz'
 * s.succ # => "100aa00aa"
 * s = '1.9.9'
 * s.succ # => "2.0.0"
 * ```
 *
 * @param[in]  orig  Predecessor string.
 * @return     Successor string.
 */
VALUE rb_str_succ(VALUE orig);

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[in]  str  A C string.
 * @return     `strlen`, casted to `long`.
 */
static inline long
rbimpl_strlen(const char *str)
{
    return RBIMPL_CAST((long)strlen(str));
}

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[in]  str  A C string literal.
 * @return     Corresponding Ruby string.
 */
static inline VALUE
rbimpl_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_str_new_static(str, len);
}

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[in]  str  A C string literal.
 * @return     Corresponding Ruby string.
 */
static inline VALUE
rbimpl_usascii_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_usascii_str_new_static(str, len);
}

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[in]  str  A C string literal.
 * @return     Corresponding Ruby string.
 */
static inline VALUE
rbimpl_utf8_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_utf8_str_new_static(str, len);
}

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[in]  str  A C string literal.
 * @return     Corresponding Ruby string.
 */
static inline VALUE
rbimpl_external_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_external_str_new(str, len);
}

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[in]  str  A C string literal.
 * @return     Corresponding Ruby string.
 */
static inline VALUE
rbimpl_locale_str_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_locale_str_new(str, len);
}

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[in]  str  A C string literal.
 * @return     Corresponding Ruby string.
 */
static inline VALUE
rbimpl_str_buf_new_cstr(const char *str)
{
    long len = rbimpl_strlen(str);
    VALUE buf = rb_str_buf_new(len);
    return rb_str_buf_cat(buf, str, len);
}

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[out]  buf  A string buffer.
 * @param[in]   str  A C string literal.
 * @return      `buf` itself.
 */
static inline VALUE
rbimpl_str_cat_cstr(VALUE buf, const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_str_cat(buf, str, len);
}

RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail.  Don't bother.
 *
 * @param[in]  exc  An exception class.
 * @param[in]  str  A C string literal.
 * @return     An instance of `exc`.
 */
static inline VALUE
rbimpl_exc_new_cstr(VALUE exc, const char *str)
{
    long len = rbimpl_strlen(str);
    return rb_exc_new(exc, str, len);
}

/**
 * Allocates an instance of ::rb_cString.
 *
 * @param[in]  str             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An  instance   of  ::rb_cString,  of  `len`   bytes  length,  of
 *             "binary" encoding, whose contents are verbatim copy of `str`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `str`.
 */
#define rb_str_new(str, len)                    \
    ((RBIMPL_CONSTANT_P(str) &&                 \
      RBIMPL_CONSTANT_P(len) ?                  \
      rb_str_new_static      :                  \
      rb_str_new) ((str), (len)))

/**
 * Identical to #rb_str_new, except it assumes  the passed pointer is a pointer
 * to a C string.
 *
 * @param[in]  str             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An  instance  of  ::rb_cString,   of  "binary"  encoding,  whose
 *             contents are verbatim copy of `str`.
 * @pre        `str` must not be a null pointer.
 */
#define rb_str_new_cstr(str)                    \
    ((RBIMPL_CONSTANT_P(str) ?                  \
      rbimpl_str_new_cstr    :                  \
      rb_str_new_cstr) (str))

/**
 * Identical  to  #rb_str_new, except  it  generates  a  string of  "US  ASCII"
 * encoding.  This  is different from  rb_external_str_new(), not only  for the
 * output encoding, but also it doesn't convert the contents.
 *
 * @param[in]  str             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `str`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An  instance   of  ::rb_cString,  of  `len`   bytes  length,  of
 *             "US ASCII" encoding, whose contents are verbatim copy of `str`.
 */
#define rb_usascii_str_new(str, len)            \
    ((RBIMPL_CONSTANT_P(str)    &&              \
      RBIMPL_CONSTANT_P(len)    ?               \
      rb_usascii_str_new_static :               \
      rb_usascii_str_new) ((str), (len)))

/**
 * Identical to #rb_str_new, except it generates a string of "UTF-8" encoding.
 *
 * @param[in]  str             A memory region of `len` bytes length.
 * @param[in]  len             Length  of `str`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eNoMemError  Failed to allocate `len+1` bytes.
 * @exception  rb_eArgError    `len` is negative.
 * @return     An  instance   of  ::rb_cString,  of  `len`   bytes  length,  of
 *             "UTF-8" encoding, whose contents are verbatim copy of `str`.
 */
#define rb_utf8_str_new(str, len)               \
    ((RBIMPL_CONSTANT_P(str) &&                 \
      RBIMPL_CONSTANT_P(len) ?                  \
      rb_utf8_str_new_static :                  \
      rb_utf8_str_new) ((str), (len)))

/**
 * Identical to  #rb_str_new_cstr, except it  generates a string of  "US ASCII"
 * encoding.    It   can   also   be   seen   as   a   routine   Identical   to
 * #rb_usascii_str_new, except it assumes the passed  pointer is a pointer to a
 * C string.
 *
 * @param[in]  str             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An  instance  of ::rb_cString,  of  "US  ASCII" encoding,  whose
 *             contents are verbatim copy of `str`.
 * @pre        `str` must not be a null pointer.
 */
#define rb_usascii_str_new_cstr(str)            \
    ((RBIMPL_CONSTANT_P(str)      ?             \
      rbimpl_usascii_str_new_cstr :             \
      rb_usascii_str_new_cstr) (str))

/**
 * Identical  to #rb_str_new_cstr,  except  it generates  a  string of  "UTF-8"
 * encoding.  It can  also be seen as a routine  Identical to #rb_utf8_str_new,
 * except it assumes the passed pointer is a pointer to a C string.
 *
 * @param[in]  str             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An instance of ::rb_cString, of "UTF-8" encoding, whose contents
 *             are verbatim copy of `str`.
 * @pre        `str` must not be a null pointer.
 */
#define rb_utf8_str_new_cstr(str)               \
    ((RBIMPL_CONSTANT_P(str)   ?                \
      rbimpl_utf8_str_new_cstr :                \
      rb_utf8_str_new_cstr) (str))

/**
 * Identical  to #rb_str_new_cstr,  except it  generates a  string of  "default
 * external" encoding.
 *
 * @param[in]  str             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default internal"  to "default external" is  fully defined over
 *             the  given  contents, then  the  return  value  is a  string  of
 *             "default external"  encoding, whose  contents are  the converted
 *             ones.  Otherwise the string is a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 * @pre        `str` must not be a null pointer.
 */
#define rb_external_str_new_cstr(str)           \
    ((RBIMPL_CONSTANT_P(str)       ?            \
      rbimpl_external_str_new_cstr :            \
      rb_external_str_new_cstr) (str))

/**
 * Identical  to #rb_external_str_new_cstr,  except  it generates  a string  of
 * "locale" encoding instead of "default external".
 *
 * @param[in]  str             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An instance  of ::rb_cString.  In case  encoding conversion from
 *             "default internal" to  "locale" is fully defined  over the given
 *             contents,  then  the  return  value  is  a  string  of  "locale"
 *             encoding, whose contents are  the converted ones.  Otherwise the
 *             string is a junk.
 * @warning    It doesn't raise on a conversion failure and silently ends up in
 *             a  corrupted  output.  You  can  know  the failure  by  querying
 *             `valid_encoding?` of the result object.
 * @pre        `str` must not be a null pointer.
 */
#define rb_locale_str_new_cstr(str)             \
    ((RBIMPL_CONSTANT_P(str)     ?              \
      rbimpl_locale_str_new_cstr :              \
      rb_locale_str_new_cstr) (str))

/**
 * Identical to #rb_str_new_cstr, except done differently.
 *
 * @param[in]  str             A C string.
 * @exception  rb_eNoMemError  Failed to allocate memory.
 * @return     An  instance  of  ::rb_cString,   of  "binary"  encoding,  whose
 *             contents are verbatim copy of `str`.
 * @pre        `str` must not be a null pointer.
 */
#define rb_str_buf_new_cstr(str)                \
    ((RBIMPL_CONSTANT_P(str)  ?                 \
      rbimpl_str_buf_new_cstr :                 \
      rb_str_buf_new_cstr) (str))

/**
 * Identical to rb_str_cat(), except it assumes the passed pointer is a pointer
 * to a C string.
 *
 * @param[out]  buf                 Destination object.
 * @param[in]   str                 Contents to append.
 * @exception   rb_eArgError        Result string too big.
 * @return      The passed `buf`.
 * @pre         `buf` must not be any arbitrary objects except ::RString.
 * @pre         `str` must not be a null pointer.
 * @post        `buf` has the contents of `str` appended.
 */
#define rb_str_cat_cstr(buf, str)               \
    ((RBIMPL_CONSTANT_P(str) ?                  \
      rbimpl_str_cat_cstr    :                  \
      rb_str_cat_cstr) ((buf), (str)))

/**
 * Identical to rb_exc_new(), except it assumes the passed pointer is a pointer
 * to a C string.
 *
 * @param[out]  exc  A subclass of ::rb_eException.
 * @param[in]   str  Message to raise.
 * @return      An instance of `exc` whose message is `str`.
 * @pre         `str` must not be a null pointer.
 */
#define rb_exc_new_cstr(exc, str)               \
    ((RBIMPL_CONSTANT_P(str) ?                  \
      rbimpl_exc_new_cstr    :                  \
      rb_exc_new_cstr) ((exc), (str)))

#define rb_str_new2 rb_str_new_cstr                  /**< @old{rb_str_new_cstr} */
#define rb_str_new3 rb_str_new_shared                /**< @old{rb_str_new_shared} */
#define rb_str_new4 rb_str_new_frozen                /**< @old{rb_str_new_frozen} */
#define rb_str_new5 rb_str_new_with_class            /**< @old{rb_str_new_with_class} */
#define rb_str_buf_new2 rb_str_buf_new_cstr          /**< @old{rb_str_buf_new_cstr} */
#define rb_usascii_str_new2 rb_usascii_str_new_cstr  /**< @old{rb_usascii_str_new_cstr} */
#define rb_str_buf_cat rb_str_cat                    /**< @alias{rb_str_cat} */
#define rb_str_buf_cat2 rb_str_cat_cstr              /**< @old{rb_usascii_str_new_cstr} */
#define rb_str_cat2 rb_str_cat_cstr                  /**< @old{rb_str_cat_cstr} */

/**
 * Length of a string literal.
 *
 * @param[in]  str  A C String literal.
 * @return     An integer  constant expression that represents  `str`'s length,
 *             in bytes, not including the terminating NUL character.
 */
#define rb_strlen_lit(str) (sizeof(str "") - 1)

/**
 * Identical to rb_str_new_static(), except it cannot take string variables.
 *
 * @param[in]  str  A C string literal.
 * @pre        `str` must not be a variable.
 * @return     An instance of ::rb_cString, of "binary" encoding, whose backend
 *             storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 */
#define rb_str_new_lit(str) rb_str_new_static((str), rb_strlen_lit(str))

/**
 * Identical  to  rb_usascii_str_new_static(),  except it  cannot  take  string
 * variables.
 *
 * @param[in]  str           A C string literal.
 * @pre        `str` must not be a variable.
 * @return     An  instance  of ::rb_cString,  of  "US  ASCII" encoding,  whose
 *             backend storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 */
#define rb_usascii_str_new_lit(str) rb_usascii_str_new_static((str), rb_strlen_lit(str))

/**
 * Identical  to   rb_utf8_str_new_static(),  except  it  cannot   take  string
 * variables.
 *
 * @param[in]  str           A C string literal.
 * @pre        `str` must not be a variable.
 * @return     An instance of ::rb_cString,  of "UTF-8" encoding, whose backend
 *             storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 */
#define rb_utf8_str_new_lit(str) rb_utf8_str_new_static((str), rb_strlen_lit(str))

/**
 * Identical  to   rb_enc_str_new_static(),  except   it  cannot   take  string
 * variables.
 *
 * @param[in]  str           A C string literal.
 * @param[in]  enc           A pointer to an encoding.
 * @pre        `str` must not be a variable.
 * @return     An  instance  of ::rb_cString,  of  the  passed encoding,  whose
 *             backend storage is the passed C string literal.
 * @warning    It is  a very  bad idea to  write to a  C string  literal (often
 *             immediate  SEGV shall  occur).  Consider  return values  of this
 *             function be read-only.
 */
#define rb_enc_str_new_lit(str, enc) rb_enc_str_new_static((str), rb_strlen_lit(str), (enc))

#define rb_str_new_literal(str) rb_str_new_lit(str)                    /**< @alias{rb_str_new_lit} */
#define rb_usascii_str_new_literal(str) rb_usascii_str_new_lit(str)    /**< @alias{rb_usascii_str_new_lit} */
#define rb_utf8_str_new_literal(str) rb_utf8_str_new_lit(str)          /**< @alias{rb_utf8_str_new_lit} */
#define rb_enc_str_new_literal(str, enc) rb_enc_str_new_lit(str, enc)  /**< @alias{rb_enc_str_new_lit} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_STRING_H */
