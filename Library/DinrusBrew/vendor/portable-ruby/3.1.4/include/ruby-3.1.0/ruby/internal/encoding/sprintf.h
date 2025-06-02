#ifndef RUBY_INTERNAL_ENCODING_SPRINTF_H             /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_SPRINTF_H
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
#include "ruby/internal/config.h"
#include <stdarg.h>
#include "ruby/internal/attr/format.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/encoding/encoding.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Identical to  rb_sprintf(), except it  additionally takes an  encoding.  The
 * passed encoding rules  both the incoming format specifier  and the resulting
 * string.
 *
 * @param[in]  enc  Encoding of `fmt`.
 * @param[in]  fmt  A `printf`-like format specifier.
 * @param[in]  ...  Variadic number of contents to format.
 * @return     A rendered new instance of ::rb_cString, of `enc` encoding.
 */
VALUE rb_enc_sprintf(rb_encoding *enc, const char *fmt, ...);

RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 0)
/**
 * Identical  to  rb_enc_sprintf(), except  it  takes  a `va_list`  instead  of
 * variadic  arguments.   It  can  also  be seen  as  a  routine  identical  to
 * rb_vsprintf(), except it additionally takes an encoding.
 *
 * @param[in]  enc  Encoding of `fmt`.
 * @param[in]  fmt  A `printf`-like format specifier.
 * @param[in]  ap   Contents to format.
 * @return     A rendered new instance of ::rb_cString, of `enc` encoding.
 */
VALUE rb_enc_vsprintf(rb_encoding *enc, const char *fmt, va_list ap);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((3))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 3, 4)
/**
 * Identical to rb_raise(), except it additionally takes an encoding.
 *
 * @param[in]  enc  Encoding of the generating exception.
 * @param[in]  exc  A subclass of ::rb_eException.
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 * @param[in]  ...  Contents of the message.
 * @exception  exc  The specified exception.
 * @note       It never returns.
 */
void rb_enc_raise(rb_encoding *enc, VALUE exc, const char *fmt, ...);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_SPRINTF_H */
