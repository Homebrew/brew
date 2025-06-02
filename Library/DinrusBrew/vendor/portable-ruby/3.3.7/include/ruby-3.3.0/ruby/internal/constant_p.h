#ifndef RBIMPL_CONSTANT_P_H                          /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_CONSTANT_P_H
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
 * @brief      Defines #RBIMPL_CONSTANT_P.
 *
 * Note that __builtin_constant_p can be applicable inside of inline functions,
 * according to GCC manual.  Clang lacks that feature, though.
 *
 * @see https://bugs.llvm.org/show_bug.cgi?id=4898
 * @see https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html
 */
#include "ruby/internal/has/builtin.h"

/** Wraps (or simulates) `__builtin_constant_p` */
#if RBIMPL_HAS_BUILTIN(__builtin_constant_p)
# define RBIMPL_CONSTANT_P(expr) __builtin_constant_p(expr)
#else
# define RBIMPL_CONSTANT_P(expr) 0
#endif

#endif /* RBIMPL_CONSTANT_P_H */
