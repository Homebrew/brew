#ifndef RBIMPL_STATIC_ASSERT_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_STATIC_ASSERT_H
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
 * @brief      Defines #RBIMPL_STATIC_ASSERT.
 */
#include <assert.h>
#include "ruby/internal/has/extension.h"
#include "ruby/internal/compiler_since.h"

/** @cond INTERNAL_MACRO */
#if defined(__cplusplus) && defined(__cpp_static_assert)
# /* https://isocpp.org/std/standing-documents/sd-6-sg10-feature-test-recommendations */
# define RBIMPL_STATIC_ASSERT0 static_assert

#elif defined(__cplusplus) && RBIMPL_COMPILER_SINCE(MSVC, 16, 0, 0)
# define RBIMPL_STATIC_ASSERT0 static_assert

#elif defined(__INTEL_CXX11_MODE__)
# define RBIMPL_STATIC_ASSERT0 static_assert

#elif defined(__cplusplus) && __cplusplus >= 201103L
# define RBIMPL_STATIC_ASSERT0 static_assert

#elif defined(__cplusplus) && RBIMPL_HAS_EXTENSION(cxx_static_assert)
# define RBIMPL_STATIC_ASSERT0 __extension__ static_assert

#elif defined(__GXX_EXPERIMENTAL_CXX0X__) && __GXX_EXPERIMENTAL_CXX0X__
# define RBIMPL_STATIC_ASSERT0 __extension__ static_assert

#elif defined(__STDC_VERSION__) && RBIMPL_HAS_EXTENSION(c_static_assert)
# define RBIMPL_STATIC_ASSERT0 __extension__ _Static_assert

#elif defined(__STDC_VERSION__) && RBIMPL_COMPILER_SINCE(GCC, 4, 6, 0)
# define RBIMPL_STATIC_ASSERT0 __extension__ _Static_assert

#elif defined(static_assert)
# /* Take <assert.h> definition */
# define RBIMPL_STATIC_ASSERT0 static_assert
#endif
/** @endcond */

/**
 * @brief  Wraps (or simulates) `static_assert`
 * @param  name  Valid C/C++ identifier, describing the assertion.
 * @param  expr  Expression to assert.
 * @note   `name` shall not be a string literal.
 */
#if defined(__DOXYGEN__)
# define RBIMPL_STATIC_ASSERT static_assert

#elif defined(RBIMPL_STATIC_ASSERT0)
# define RBIMPL_STATIC_ASSERT(name, expr) \
    RBIMPL_STATIC_ASSERT0(expr, # name ": " # expr)

#else
# define RBIMPL_STATIC_ASSERT(name, expr) \
    typedef int static_assert_ ## name ## _check[1 - 2 * !(expr)]
#endif

#endif /* RBIMPL_STATIC_ASSERT_H */
