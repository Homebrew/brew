#ifndef RUBY_INTERNAL_ENCODING_RE_H                  /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_RE_H
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

#include "ruby/internal/dllexport.h"
#include "ruby/internal/encoding/encoding.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Identical to rb_reg_new(), except it additionally takes an encoding.
 *
 * @param[in]  ptr              A memory region of `len` bytes length.
 * @param[in]  len              Length of  `ptr`, in  bytes, not  including the
 *                              terminating NUL character.
 * @param[in]  enc              Encoding of `ptr`.
 * @param[in]  opts             Options e.g. ONIG_OPTION_MULTILINE.
 * @exception  rb_eRegexpError  Failed to compile `ptr`.
 * @return     An allocated  new instance  of ::rb_cRegexp, of  `enc` encoding,
 *             whose expression is compiled according to `ptr`.
 */
VALUE rb_enc_reg_new(const char *ptr, long len, rb_encoding *enc, int opts);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_RE_H */
