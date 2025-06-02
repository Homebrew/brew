#ifndef RBIMPL_HAS_ATTRIBUTE_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_HAS_ATTRIBUTE_H
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
 * @brief      Defines #RBIMPL_HAS_ATTRIBUTE.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/compiler_since.h"

#if defined(__has_attribute)
# if __has_attribute(pure) || RBIMPL_COMPILER_IS(GCC)
#  /* FreeBSD's   <sys/cdefs.h>   defines   its   own   *broken*   version   of
#   * __has_attribute.   Cygwin copied  that  content  to be  a  victim of  the
#   * broken-ness.  We don't take them into account. */
#  define RBIMPL_HAVE___HAS_ATTRIBUTE 1
# endif
#endif

/** Wraps (or simulates) `__has_attribute`. */
#if defined(RBIMPL_HAVE___HAS_ATTRIBUTE)
# define RBIMPL_HAS_ATTRIBUTE(_) __has_attribute(_)

#elif RBIMPL_COMPILER_IS(GCC)
# /* GCC  <= 4  lack __has_attribute  predefined macro,  while have  attributes
#  * themselves.  We can simulate the macro like the following: */
# define RBIMPL_HAS_ATTRIBUTE(_) (RBIMPL_HAS_ATTRIBUTE_ ## _)
# define RBIMPL_HAS_ATTRIBUTE_aligned                    RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# define RBIMPL_HAS_ATTRIBUTE_alloc_size                 RBIMPL_COMPILER_SINCE(GCC, 4, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_artificial                 RBIMPL_COMPILER_SINCE(GCC, 4, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_always_inline              RBIMPL_COMPILER_SINCE(GCC, 3, 1, 0)
# define RBIMPL_HAS_ATTRIBUTE_cdecl                      RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# define RBIMPL_HAS_ATTRIBUTE_cold                       RBIMPL_COMPILER_SINCE(GCC, 4, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_const                      RBIMPL_COMPILER_SINCE(GCC, 2, 6, 0)
# define RBIMPL_HAS_ATTRIBUTE_deprecated                 RBIMPL_COMPILER_SINCE(GCC, 3, 1, 0)
# define RBIMPL_HAS_ATTRIBUTE_dllexport                  RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# define RBIMPL_HAS_ATTRIBUTE_dllimport                  RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# define RBIMPL_HAS_ATTRIBUTE_error                      RBIMPL_COMPILER_SINCE(GCC, 4, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_format                     RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# define RBIMPL_HAS_ATTRIBUTE_hot                        RBIMPL_COMPILER_SINCE(GCC, 4, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_leaf                       RBIMPL_COMPILER_SINCE(GCC, 4, 6, 0)
# define RBIMPL_HAS_ATTRIBUTE_malloc                     RBIMPL_COMPILER_SINCE(GCC, 3, 0, 0)
# define RBIMPL_HAS_ATTRIBUTE_no_address_safety_analysis RBIMPL_COMPILER_SINCE(GCC, 4, 8, 0)
# define RBIMPL_HAS_ATTRIBUTE_no_sanitize_address        RBIMPL_COMPILER_SINCE(GCC, 4, 8, 0)
# define RBIMPL_HAS_ATTRIBUTE_no_sanitize_undefined      RBIMPL_COMPILER_SINCE(GCC, 4, 9, 0)
# define RBIMPL_HAS_ATTRIBUTE_noinline                   RBIMPL_COMPILER_SINCE(GCC, 3, 1, 0)
# define RBIMPL_HAS_ATTRIBUTE_nonnull                    RBIMPL_COMPILER_SINCE(GCC, 3, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_noreturn                   RBIMPL_COMPILER_SINCE(GCC, 2, 5, 0)
# define RBIMPL_HAS_ATTRIBUTE_nothrow                    RBIMPL_COMPILER_SINCE(GCC, 3, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_pure                       RBIMPL_COMPILER_SINCE(GCC, 2,96, 0)
# define RBIMPL_HAS_ATTRIBUTE_returns_nonnull            RBIMPL_COMPILER_SINCE(GCC, 4, 9, 0)
# define RBIMPL_HAS_ATTRIBUTE_returns_twice              RBIMPL_COMPILER_SINCE(GCC, 4, 1, 0)
# define RBIMPL_HAS_ATTRIBUTE_stdcall                    RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# define RBIMPL_HAS_ATTRIBUTE_unused                     RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# define RBIMPL_HAS_ATTRIBUTE_visibility                 RBIMPL_COMPILER_SINCE(GCC, 3, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_warn_unused_result         RBIMPL_COMPILER_SINCE(GCC, 3, 4, 0)
# define RBIMPL_HAS_ATTRIBUTE_warning                    RBIMPL_COMPILER_SINCE(GCC, 4, 3, 0)
# define RBIMPL_HAS_ATTRIBUTE_weak                       RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# /* Note that "0, 0, 0" might be inaccurate. */

#elif RBIMPL_COMPILER_IS(SunPro)
# /* Oracle Solaris Studio 12.4 (cc version 5.11) introduced __has_attribute.
#  * Before that, following attributes were available. */
# /* See https://docs.oracle.com/cd/F24633_01/index.html */
# define RBIMPL_HAS_ATTRIBUTE(_) (RBIMPL_HAS_ATTRIBUTE_ ## _)
# define RBIMPL_HAS_ATTRIBUTE_alias                      RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_aligned                    RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_always_inline              RBIMPL_COMPILER_SINCE(SunPro, 5, 10, 0)
# define RBIMPL_HAS_ATTRIBUTE_const                      RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_constructor                RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_destructor                 RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_malloc                     RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_noinline                   RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_noreturn                   RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_packed                     RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_pure                       RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_returns_twice              RBIMPL_COMPILER_SINCE(SunPro, 5, 10, 0)
# define RBIMPL_HAS_ATTRIBUTE_vector_size                RBIMPL_COMPILER_SINCE(SunPro, 5, 10, 0)
# define RBIMPL_HAS_ATTRIBUTE_visibility                 RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)
# define RBIMPL_HAS_ATTRIBUTE_weak                       RBIMPL_COMPILER_SINCE(SunPro, 5,  9, 0)

#elif defined (_MSC_VER)
# define RBIMPL_HAS_ATTRIBUTE(_) 0
# /* Fallback below doesn't work: see win32/Makefile.sub */

#else
# /* Take config.h definition when available. */
# define RBIMPL_HAS_ATTRIBUTE(_) ((RBIMPL_HAS_ATTRIBUTE_ ## _)+0)
# ifdef ALWAYS_INLINE
#  define RBIMPL_HAS_ATTRIBUTE_always_inline 1
# endif
# ifdef FUNC_CDECL
#  define RBIMPL_HAS_ATTRIBUTE_cdecl 1
# endif
# ifdef CONSTFUNC
#  define RBIMPL_HAS_ATTRIBUTE_const 1
# endif
# ifdef DEPRECATED
#  define RBIMPL_HAS_ATTRIBUTE_deprecated 1
# endif
# ifdef ERRORFUNC
#  define RBIMPL_HAS_ATTRIBUTE_error 1
# endif
# ifdef FUNC_FASTCALL
#  define RBIMPL_HAS_ATTRIBUTE_fastcall 1
# endif
# ifdef PUREFUNC
#  define RBIMPL_HAS_ATTRIBUTE_pure 1
# endif
# ifdef NO_ADDRESS_SAFETY_ANALYSIS
#  define RBIMPL_HAS_ATTRIBUTE_no_address_safety_analysis 1
# endif
# ifdef NO_SANITIZE
#  define RBIMPL_HAS_ATTRIBUTE_no_sanitize 1
# endif
# ifdef NO_SANITIZE_ADDRESS
#  define RBIMPL_HAS_ATTRIBUTE_no_sanitize_address 1
# endif
# ifdef NOINLINE
#  define RBIMPL_HAS_ATTRIBUTE_noinline 1
# endif
# ifdef RBIMPL_FUNC_NONNULL
#  define RBIMPL_HAS_ATTRIBUTE_nonnull 1
# endif
# ifdef NORETURN
#  define RBIMPL_HAS_ATTRIBUTE_noreturn 1
# endif
# ifdef FUNC_OPTIMIZED
#  define RBIMPL_HAS_ATTRIBUTE_optimize 1
# endif
# ifdef FUNC_STDCALL
#  define RBIMPL_HAS_ATTRIBUTE_stdcall 1
# endif
# ifdef MAYBE_UNUSED
#  define RBIMPL_HAS_ATTRIBUTE_unused 1
# endif
# ifdef WARN_UNUSED_RESULT
#  define RBIMPL_HAS_ATTRIBUTE_warn_unused_result 1
# endif
# ifdef WARNINGFUNC
#  define RBIMPL_HAS_ATTRIBUTE_warning 1
# endif
# ifdef WEAK
#  define RBIMPL_HAS_ATTRIBUTE_weak 1
# endif
#endif

#endif /* RBIMPL_HAS_ATTRIBUTE_H */
