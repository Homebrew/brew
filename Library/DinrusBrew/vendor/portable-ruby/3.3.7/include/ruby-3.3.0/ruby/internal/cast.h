#ifndef RBIMPL_CAST_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_CAST_H
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
 * @brief      Defines RBIMPL_CAST.
 *
 * This casting macro makes sense only inside  of other macros that are part of
 * public headers.  They could be used  from C++, and C-style casts could issue
 * warnings.  Ruby internals are pure C so they should not bother.
 */
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/has/warning.h"
#include "ruby/internal/warning_push.h"

#if ! defined(__cplusplus)
# define RBIMPL_CAST(expr) (expr)

#elif RBIMPL_COMPILER_SINCE(GCC, 4, 6, 0)
# /* g++ has -Wold-style-cast since 1997 or so, but its _Pragma is broken. */
# /* See https://gcc.godbolt.org/z/XWhU6J */
# define RBIMPL_CAST(expr) (expr)
# pragma GCC diagnostic ignored "-Wold-style-cast"

#elif RBIMPL_HAS_WARNING("-Wold-style-cast")
# define RBIMPL_CAST(expr)                   \
    RBIMPL_WARNING_PUSH()                    \
    RBIMPL_WARNING_IGNORED(-Wold-style-cast) \
    (expr)                                  \
    RBIMPL_WARNING_POP()

#else
# define RBIMPL_CAST(expr) (expr)
#endif

#endif /* RBIMPL_CAST_H */
