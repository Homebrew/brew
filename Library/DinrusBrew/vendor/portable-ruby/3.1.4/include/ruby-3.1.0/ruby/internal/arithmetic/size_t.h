#ifndef RBIMPL_ARITHMETIC_SIZE_T_H                   /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_SIZE_T_H
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
 * @brief      Arithmetic conversion between C's `size_t` and Ruby's.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/arithmetic/int.h"
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/arithmetic/long_long.h"
#include "ruby/backward/2/long_long.h"

#if defined(__DOXYGEN__)
# /** Converts a C's `size_t` into an instance of ::rb_cInteger. */
# define RB_SIZE2NUM RB_ULONG2NUM
# /** Converts a C's `ssize_t` into an instance of ::rb_cInteger. */
# define RB_SSIZE2NUM RB_LONG2NUM
#elif SIZEOF_SIZE_T == SIZEOF_LONG_LONG
# define RB_SIZE2NUM RB_ULL2NUM
# define RB_SSIZE2NUM RB_LL2NUM
#elif SIZEOF_SIZE_T == SIZEOF_LONG
# define RB_SIZE2NUM RB_ULONG2NUM
# define RB_SSIZE2NUM RB_LONG2NUM
#else
# define RB_SIZE2NUM RB_UINT2NUM
# define RB_SSIZE2NUM RB_INT2NUM
#endif

#if defined(__DOXYGEN__)
# /** Converts an instance of ::rb_cInteger into C's `size_t`. */
# define RB_NUM2SIZE RB_NUM2ULONG
# /** Converts an instance of ::rb_cInteger into C's `ssize_t`. */
# define RB_NUM2SSIZE RB_NUM2LONG
#elif SIZEOF_SIZE_T == SIZEOF_LONG_LONG
# define RB_NUM2SIZE RB_NUM2ULL
# define RB_NUM2SSIZE RB_NUM2LL
#elif SIZEOF_SIZE_T == SIZEOF_LONG
# define RB_NUM2SIZE RB_NUM2ULONG
# define RB_NUM2SSIZE RB_NUM2LONG
#else
# define RB_NUM2SIZE RB_NUM2UINT
# define RB_NUM2SSIZE RB_NUM2INT
#endif

#define NUM2SIZET RB_NUM2SIZE   /**< @old{RB_NUM2SIZE} */
#define SIZET2NUM RB_SIZE2NUM   /**< @old{RB_SIZE2NUM} */
#define NUM2SSIZET RB_NUM2SSIZE /**< @old{RB_NUM2SSIZE} */
#define SSIZET2NUM RB_SSIZE2NUM /**< @old{RB_SSIZE2NUM} */

#endif /* RBIMPL_ARITHMETIC_SIZE_T_H */
