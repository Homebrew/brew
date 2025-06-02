#ifndef RBIMPL_ATTR_CONSTEXPR_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_CONSTEXPR_H
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
 * @brief      #RBIMPL_ATTR_CONSTEXPR.
 */
#include "ruby/internal/has/feature.h"
#include "ruby/internal/compiler_is.h"

/** @cond INTERNAL_MACRO */
#if ! defined(__cplusplus)
# /* Makes no sense. */
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 0
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 0

#elif defined(__cpp_constexpr)
# /* https://isocpp.org/std/standing-documents/sd-6-sg10-feature-test-recommendations */
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 (__cpp_constexpr >= 200704L)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 (__cpp_constexpr >= 201304L)

#elif RBIMPL_COMPILER_SINCE(MSVC, 19, 0, 0)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 RBIMPL_COMPILER_SINCE(MSVC, 19, 00, 00)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 RBIMPL_COMPILER_SINCE(MSVC, 19, 11, 00)

#elif RBIMPL_COMPILER_SINCE(SunPro, 5, 13, 0)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 (__cplusplus >= 201103L)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 (__cplusplus >= 201402L)

#elif RBIMPL_COMPILER_SINCE(GCC, 4, 9, 0)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 (__cplusplus >= 201103L)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 (__cplusplus >= 201402L)

#elif RBIMPL_HAS_FEATURE(cxx_relaxed_constexpr)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 1
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 1

#elif RBIMPL_HAS_FEATURE(cxx_constexpr)
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 1
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 0

#else
# /* :FIXME: icpc must have constexpr but don't know how to detect. */
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX11 0
# define RBIMPL_HAS_ATTR_CONSTEXPR_CXX14 0
#endif
/** @endcond */

/** Wraps (or simulates) C++11 `constexpr`.  */
#if RBIMPL_HAS_ATTR_CONSTEXPR_CXX14
# define RBIMPL_ATTR_CONSTEXPR(_) constexpr

#elif RBIMPL_HAS_ATTR_CONSTEXPR_CXX11
# define RBIMPL_ATTR_CONSTEXPR(_) RBIMPL_ATTR_CONSTEXPR_ ## _
# define RBIMPL_ATTR_CONSTEXPR_CXX11 constexpr
# define RBIMPL_ATTR_CONSTEXPR_CXX14 /* void */

#else
# define RBIMPL_ATTR_CONSTEXPR(_) /* void */
#endif

/** Enables #RBIMPL_ATTR_CONSTEXPR if and only if. ! #RUBY_DEBUG. */
#if !RUBY_DEBUG
# define RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(_) RBIMPL_ATTR_CONSTEXPR(_)
#else
# define RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(_) /* void */
#endif

#endif /* RBIMPL_ATTR_CONSTEXPR_H */
