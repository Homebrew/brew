#ifndef RUBY_BACKWARD2_ASSUME_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_BACKWARD2_ASSUME_H
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
 * @brief      Defines #ASSUME / #RB_LIKELY / #UNREACHABLE
 */
#include "ruby/internal/config.h"
#include "ruby/internal/assume.h"
#include "ruby/internal/has/builtin.h"

#undef  ASSUME             /* Kill config.h definition */
#undef  UNREACHABLE        /* Kill config.h definition */
#define ASSUME             RBIMPL_ASSUME             /**< @old{RBIMPL_ASSUME} */
#define UNREACHABLE        RBIMPL_UNREACHABLE()      /**< @old{RBIMPL_UNREACHABLE} */
#define UNREACHABLE_RETURN RBIMPL_UNREACHABLE_RETURN /**< @old{RBIMPL_UNREACHABLE_RETURN} */

/* likely */
#if RBIMPL_HAS_BUILTIN(__builtin_expect)
/**
 * Asserts that the given Boolean expression likely holds.
 *
 * @param  x  An expression that likely holds.
 *
 * @note  Consider this macro carefully.  It has been here since when CPUs were
 *        like  babies,  but  contemporary  processors are  beasts.   They  are
 *        smarter than  mare mortals like  us today.  Their  branch predictions
 *        highly expectedly outperform your use of this macro.
 */
# define RB_LIKELY(x)   (__builtin_expect(!!(x), 1))

/**
 * Asserts that the given Boolean expression likely doesn't hold.
 *
 * @param  x  An expression that likely doesn't hold.
 */
# define RB_UNLIKELY(x) (__builtin_expect(!!(x), 0))
#else
# define RB_LIKELY(x)   (x)
# define RB_UNLIKELY(x) (x)
#endif

#endif /* RUBY_BACKWARD2_ASSUME_H */
