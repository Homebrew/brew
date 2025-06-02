#ifndef RBIMPL_STDBOOL_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_STDBOOL_H
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
 * @brief      C99 shim for <stdbool.h>
 */
#include "ruby/internal/config.h"

#if defined(__bool_true_false_are_defined)
# /* Take that. */

#elif defined(__cplusplus)
# /* bool is a keyword in C++. */
# if defined(HAVE_STDBOOL_H) && (__cplusplus >= 201103L)
#  include <cstdbool>
# endif
#
# ifndef __bool_true_false_are_defined
#  define __bool_true_false_are_defined
# endif

#elif defined(HAVE_STDBOOL_H)
# /* Take stdbool.h definition. */
# include <stdbool.h>

#else
typedef unsigned char _Bool;
# /* See also http://www.open-std.org/jtc1/sc22/wg14/www/docs/n2229.htm */
# define bool  _Bool
# define true  ((_Bool)+1)
# define false ((_Bool)+0)
# define __bool_true_false_are_defined
#endif

#endif /* RBIMPL_STDBOOL_H */
