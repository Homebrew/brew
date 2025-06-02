#ifndef RBIMPL_HAS_CPP_ATTRIBUTE_H                   /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_HAS_CPP_ATTRIBUTE_H
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
 * @brief      Defines #RBIMPL_HAS_CPP_ATTRIBUTE.
 */
#include "ruby/internal/compiler_is.h"
#include "ruby/internal/compiler_since.h"

/** @cond INTERNAL_MACRO */
#if RBIMPL_COMPILER_IS(SunPro)
# /* Oracle Developer Studio 12.5's C++  preprocessor is reportedly broken.  We
#  * could simulate  __has_cpp_attribute like below,  but don't know  the exact
#  * list of which version supported which attribute.  Just kill everything for
#  * now.  If you can please :FIXME: */
# /* https://unicode-org.atlassian.net/browse/ICU-12893 */
# /* https://github.com/boostorg/config/pull/95 */
# define RBIMPL_HAS_CPP_ATTRIBUTE0(_) 0

#elif defined(__has_cpp_attribute)
# define RBIMPL_HAS_CPP_ATTRIBUTE0(_) __has_cpp_attribute(_)

#elif RBIMPL_COMPILER_IS(MSVC)
# /* MSVC has  never updated  its __cplusplus  since forever  (unless specified
#  * explicitly by a compiler flag).   They also lack __has_cpp_attribute until
#  * 2019.  However, they do have attributes since 2015 or so. */
# /* https://docs.microsoft.com/en-us/cpp/overview/visual-cpp-language-conformance */
# define RBIMPL_HAS_CPP_ATTRIBUTE0(_) (RBIMPL_HAS_CPP_ATTRIBUTE_ ## _)
# define RBIMPL_HAS_CPP_ATTRIBUTE_noreturn           200809 * RBIMPL_COMPILER_SINCE(MSVC, 19, 00, 0)
# define RBIMPL_HAS_CPP_ATTRIBUTE_carries_dependency 200809 * RBIMPL_COMPILER_SINCE(MSVC, 19, 00, 0)
# define RBIMPL_HAS_CPP_ATTRIBUTE_deprecated         201309 * RBIMPL_COMPILER_SINCE(MSVC, 19, 10, 0)
# define RBIMPL_HAS_CPP_ATTRIBUTE_fallthrough        201603 * RBIMPL_COMPILER_SINCE(MSVC, 19, 10, 0)
# define RBIMPL_HAS_CPP_ATTRIBUTE_maybe_unused       201603 * RBIMPL_COMPILER_SINCE(MSVC, 19, 11, 0)
# define RBIMPL_HAS_CPP_ATTRIBUTE_nodiscard          201603 * RBIMPL_COMPILER_SINCE(MSVC, 19, 11, 0)

#elif RBIMPL_COMPILER_BEFORE(Clang, 3, 6, 0)
# /* Clang  3.6.0  introduced  __has_cpp_attribute.  Prior  to  that  following
#  * attributes were already there. */
# /* https://clang.llvm.org/cxx_status.html */
# define RBIMPL_HAS_CPP_ATTRIBUTE0(_) (RBIMPL_HAS_CPP_ATTRIBUTE_ ## _)
# define RBIMPL_HAS_CPP_ATTRIBUTE_noreturn           200809 * RBIMPL_COMPILER_SINCE(Clang, 3, 3, 0)
# define RBIMPL_HAS_CPP_ATTRIBUTE_deprecated         201309 * RBIMPL_COMPILER_SINCE(Clang, 3, 4, 0)

#elif RBIMPL_COMPILER_BEFORE(GCC, 5, 0, 0)
# /* GCC 5+ have __has_cpp_attribute, while 4.x had following attributes. */
# /* https://gcc.gnu.org/projects/cxx-status.html */
# define RBIMPL_HAS_CPP_ATTRIBUTE0(_) (RBIMPL_HAS_CPP_ATTRIBUTE_ ## _)
# define RBIMPL_HAS_CPP_ATTRIBUTE_noreturn           200809 * RBIMPL_COMPILER_SINCE(GCC, 4, 8, 0)
# define RBIMPL_HAS_CPP_ATTRIBUTE_deprecated         201309 * RBIMPL_COMPILER_SINCE(GCC, 4, 9, 0)

#else
# /* :FIXME:
#  * Candidate compilers to list here:
#  * - icpc: They have __INTEL_CXX11_MODE__.
#  */
# define RBIMPL_HAS_CPP_ATTRIBUTE0(_) 0
#endif
/** @endcond */

/** Wraps (or simulates) `__has_cpp_attribute`. */
#if ! defined(__cplusplus)
# /* Makes no sense. */
# define RBIMPL_HAS_CPP_ATTRIBUTE(_) 0
#else
# /* GCC needs workarounds.  See https://gcc.godbolt.org/z/jdz3pa */
# define RBIMPL_HAS_CPP_ATTRIBUTE(_) \
    ((RBIMPL_HAS_CPP_ATTRIBUTE0(_) <= __cplusplus) ? RBIMPL_HAS_CPP_ATTRIBUTE0(_) : 0)
#endif

#endif /* RBIMPL_HAS_CPP_ATTRIBUTE_H */
