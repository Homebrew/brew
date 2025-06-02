#ifndef RUBY_INTERNAL_ENCODING_SYMBOL_H              /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_SYMBOL_H
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
 * @brief      Routines to manipulate encodings of symbols.
 */

#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/encoding/encoding.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Identical to rb_intern2(), except it additionally takes an encoding.
 *
 * @param[in]  name              The name of the id.
 * @param[in]  len               Length of `name`.
 * @param[in]  enc               `name`'s encoding.
 * @exception  rb_eRuntimeError  Too many symbols.
 * @return     A (possibly new) id whose value is the given name.
 * @note       These   days  Ruby   internally   has  two   kinds  of   symbols
 *             (static/dynamic).   Symbols created  using  this function  would
 *             become static ones;  i.e. would never be  garbage collected.  It
 *             is up  to you to avoid  memory leaks.  Think twice  before using
 *             it.
 */
ID rb_intern3(const char *name, long len, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_symname_p(), except it additionally takes an encoding.
 *
 * @param[in]  str  A C string to check.
 * @param[in]  enc  `str`'s encoding.
 * @retval     1    It is a valid symbol name.
 * @retval     0    It is invalid as a symbol name.
 */
int rb_enc_symname_p(const char *str, rb_encoding *enc);

/**
 * Identical  to rb_enc_symname_p(),  except it  additionally takes  the passed
 * string's length.  This  is needed for strings containing NUL  bytes, like in
 * case of UTF-32.
 *
 * @param[in]  name  A C string to check.
 * @param[in]  len   Number of bytes of `str`.
 * @param[in]  enc   `str`'s encoding.
 * @retval     1     It is a valid symbol name.
 * @retval     0     It is invalid as a symbol name.
 */
int rb_enc_symname2_p(const char *name, long len, rb_encoding *enc);

/**
 * Identical to  rb_check_id(), except it  takes a  pointer to a  memory region
 * instead of Ruby's string.
 *
 * @param[in]  ptr                A pointer to a memory region.
 * @param[in]  len                Number of bytes of `ptr`.
 * @param[in]  enc                Encoding of `ptr`.
 * @exception  rb_eEncodingError  `ptr` contains non-ASCII according to `enc`.
 * @retval     0                  No such id ever existed in the history.
 * @retval     otherwise          The id that represents the given name.
 */
ID rb_check_id_cstr(const char *ptr, long len, rb_encoding *enc);

/**
 * Identical to rb_check_id_cstr(), except for the return type.  It can also be
 * seen as a routine identical to  rb_check_symbol(), except it takes a pointer
 * to a memory region instead of Ruby's string.
 *
 * @param[in]  ptr                A pointer to a memory region.
 * @param[in]  len                Number of bytes of `ptr`.
 * @param[in]  enc                Encoding of `ptr`.
 * @exception  rb_eEncodingError  `ptr` contains non-ASCII according to `enc`.
 * @retval     RUBY_Qnil          No such id ever existed in the history.
 * @retval     otherwise          The id that represents the given name.
 */
VALUE rb_check_symbol_cstr(const char *ptr, long len, rb_encoding *enc);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_SYMBOL_H */
