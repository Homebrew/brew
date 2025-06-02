#ifndef RUBY_BACKWARD2_LIMITS_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_BACKWARD2_LIMITS_H
/**
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
 * @brief      Historical shim for `<limits.h>`.
 *
 * The macros in this header file are obsolescent.  Does anyone really need our
 * own definition of `CHAR_BIT` today?
 */
#include "ruby/internal/config.h"

#ifdef HAVE_LIMITS_H
# include <limits.h>
#endif

#include "ruby/backward/2/long_long.h"

#ifndef LONG_MAX
# /* assuming 32bit(2's complement) long */
# define LONG_MAX 2147483647L
#endif

#ifndef LONG_MIN
# define LONG_MIN (-LONG_MAX-1)
#endif

#ifndef CHAR_BIT
# define CHAR_BIT 8
#endif

#ifdef LLONG_MAX
# /* Take that. */
#elif defined(LONG_LONG_MAX)
# define LLONG_MAX  LONG_LONG_MAX
#elif defined(_I64_MAX)
# define LLONG_MAX _I64_MAX
#else
# /* assuming 64bit(2's complement) long long */
# define LLONG_MAX 9223372036854775807LL
#endif

#ifdef LLONG_MIN
# /* Take that. */
#elif defined(LONG_LONG_MIN)
# define LLONG_MIN  LONG_LONG_MIN
#elif defined(_I64_MAX)
# define LLONG_MIN _I64_MIN
#else
# define LLONG_MIN (-LLONG_MAX-1)
#endif

#ifdef SIZE_MAX
# /* Take that. */
#elif SIZEOF_SIZE_T == SIZEOF_LONG_LONG
# define SIZE_MAX ULLONG_MAX
# define SIZE_MIN ULLONG_MIN
#elif SIZEOF_SIZE_T == SIZEOF_LONG
# define SIZE_MAX ULONG_MAX
# define SIZE_MIN ULONG_MIN
#elif SIZEOF_SIZE_T == SIZEOF_INT
# define SIZE_MAX UINT_MAX
# define SIZE_MIN UINT_MIN
#else
# define SIZE_MAX USHRT_MAX
# define SIZE_MIN USHRT_MIN
#endif

#ifdef SSIZE_MAX
# /* Take that. */
#elif SIZEOF_SIZE_T == SIZEOF_LONG_LONG
# define SSIZE_MAX LLONG_MAX
# define SSIZE_MIN LLONG_MIN
#elif SIZEOF_SIZE_T == SIZEOF_LONG
# define SSIZE_MAX LONG_MAX
# define SSIZE_MIN LONG_MIN
#elif SIZEOF_SIZE_T == SIZEOF_INT
# define SSIZE_MAX INT_MAX
# define SSIZE_MIN INT_MIN
#else
# define SSIZE_MAX SHRT_MAX
# define SSIZE_MIN SHRT_MIN
#endif

#endif /* RUBY_BACKWARD2_LIMITS_H */
