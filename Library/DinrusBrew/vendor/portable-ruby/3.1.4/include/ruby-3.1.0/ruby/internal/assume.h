#ifndef RBIMPL_ASSUME_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ASSUME_H
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
 * @brief      Defines #RBIMPL_ASSUME / #RBIMPL_UNREACHABLE.
 *
 * These macros must be defined at once because:
 *
 * - #RBIMPL_ASSUME could fallback to #RBIMPL_UNREACHABLE.
 * - #RBIMPL_UNREACHABLE could fallback to #RBIMPL_ASSUME.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/has/builtin.h"
#include "ruby/internal/warning_push.h"

/** @cond INTERNAL_MACRO */
#if RBIMPL_COMPILER_SINCE(MSVC, 13, 10, 0)
# define RBIMPL_HAVE___ASSUME

#elif RBIMPL_COMPILER_SINCE(Intel, 13, 0, 0)
# define RBIMPL_HAVE___ASSUME
#endif
/** @endcond */

/** Wraps (or simulates) `__builtin_unreachable`. */
#if RBIMPL_HAS_BUILTIN(__builtin_unreachable)
# define RBIMPL_UNREACHABLE_RETURN(_) __builtin_unreachable()

#elif defined(RBIMPL_HAVE___ASSUME)
# define RBIMPL_UNREACHABLE_RETURN(_) return (__assume(0), (_))

#else
# define RBIMPL_UNREACHABLE_RETURN(_) return (_)
#endif

/** Wraps (or simulates) `__builtin_unreachable`. */
#if RBIMPL_HAS_BUILTIN(__builtin_unreachable)
# define RBIMPL_UNREACHABLE __builtin_unreachable

#elif defined(RBIMPL_HAVE___ASSUME)
# define RBIMPL_UNREACHABLE() __assume(0)
#endif

/** Wraps (or simulates) `__assume`. */
#if RBIMPL_COMPILER_SINCE(Intel, 13, 0, 0)
# /* icc warnings are false positives.  Ignore them. */
# /* "warning #2261: __assume expression with side effects discarded" */
# define RBIMPL_ASSUME(expr)     \
    RBIMPL_WARNING_PUSH()        \
    RBIMPL_WARNING_IGNORED(2261) \
    __assume(expr)              \
    RBIMPL_WARNING_POP()

#elif defined(RBIMPL_HAVE___ASSUME)
# define RBIMPL_ASSUME __assume

#elif RBIMPL_HAS_BUILTIN(__builtin_assume)
# define RBIMPL_ASSUME __builtin_assume

#elif ! defined(RBIMPL_UNREACHABLE)
# define RBIMPL_ASSUME(_) RBIMPL_CAST((void)(_))

#else
# define RBIMPL_ASSUME(_) \
    (RB_LIKELY(!!(_)) ? RBIMPL_CAST((void)0) : RBIMPL_UNREACHABLE())
#endif

#if ! defined(RBIMPL_UNREACHABLE)
# define RBIMPL_UNREACHABLE() RBIMPL_ASSUME(0)
#endif

#endif /* RBIMPL_ASSUME_H */
