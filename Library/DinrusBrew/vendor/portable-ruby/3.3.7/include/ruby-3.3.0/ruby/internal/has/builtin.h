#ifndef RBIMPL_HAS_BUILTIN_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_HAS_BUILTIN_H
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
 * @brief      Defines #RBIMPL_HAS_BUILTIN.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/compiler_since.h"

#if defined(__has_builtin)
# if RBIMPL_COMPILER_IS(Intel)
#  /* :TODO: Intel  C Compiler  has __has_builtin (since  19.1 maybe?),  and is
#   * reportedly  broken.  We  have to  skip them.   However the  situation can
#   * change.  They might improve someday.  We need to revisit here later. */
# elif RBIMPL_COMPILER_IS(GCC) && ! __has_builtin(__builtin_alloca)
#  /* FreeBSD's   <sys/cdefs.h>   defines   its   own   *broken*   version   of
#   * __has_builtin.   Cygwin  copied  that  content  to be  a  victim  of  the
#   * broken-ness.  We don't take them into account. */
# else
#  define RBIMPL_HAVE___HAS_BUILTIN 1
# endif
#endif

/** Wraps (or simulates) `__has_builtin`. */
#if defined(RBIMPL_HAVE___HAS_BUILTIN)
# define RBIMPL_HAS_BUILTIN(_) __has_builtin(_)

#elif RBIMPL_COMPILER_IS(GCC)
# /* :FIXME: Historically  GCC has had  tons of builtins, but  it implemented
#  * __has_builtin  only  since  GCC  10.   This section  can  be  made  more
#  * granular. */
# /* https://gcc.gnu.org/bugzilla/show_bug.cgi?id=66970 */
# define RBIMPL_HAS_BUILTIN(_) (RBIMPL_HAS_BUILTIN_ ## _)
# define RBIMPL_HAS_BUILTIN___builtin_add_overflow      RBIMPL_COMPILER_SINCE(GCC, 5, 1, 0)
# define RBIMPL_HAS_BUILTIN___builtin_alloca            RBIMPL_COMPILER_SINCE(GCC, 0, 0, 0)
# define RBIMPL_HAS_BUILTIN___builtin_alloca_with_align RBIMPL_COMPILER_SINCE(GCC, 6, 1, 0)
# define RBIMPL_HAS_BUILTIN___builtin_assume            0
# /* See http://gcc.gnu.org/bugzilla/show_bug.cgi?id=52624 for bswap16. */
# define RBIMPL_HAS_BUILTIN___builtin_bswap16           RBIMPL_COMPILER_SINCE(GCC, 4, 8, 0)
#ifndef __OpenBSD__
# define RBIMPL_HAS_BUILTIN___builtin_bswap32           RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_bswap64           RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
#endif
# define RBIMPL_HAS_BUILTIN___builtin_clz               RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_clzl              RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_clzll             RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_constant_p        RBIMPL_COMPILER_SINCE(GCC, 2,95, 3)
# define RBIMPL_HAS_BUILTIN___builtin_ctz               RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_ctzl              RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_ctzll             RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_expect            RBIMPL_COMPILER_SINCE(GCC, 3, 0, 0)
# define RBIMPL_HAS_BUILTIN___builtin_mul_overflow      RBIMPL_COMPILER_SINCE(GCC, 5, 1, 0)
# define RBIMPL_HAS_BUILTIN___builtin_mul_overflow_p    RBIMPL_COMPILER_SINCE(GCC, 7, 0, 0)
# define RBIMPL_HAS_BUILTIN___builtin_popcount          RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_popcountl         RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_popcountll        RBIMPL_COMPILER_SINCE(GCC, 3, 6, 0)
# define RBIMPL_HAS_BUILTIN___builtin_rotateleft32      0
# define RBIMPL_HAS_BUILTIN___builtin_rotateleft64      0
# define RBIMPL_HAS_BUILTIN___builtin_rotateright32     0
# define RBIMPL_HAS_BUILTIN___builtin_rotateright64     0
# define RBIMPL_HAS_BUILTIN___builtin_sub_overflow      RBIMPL_COMPILER_SINCE(GCC, 5, 1, 0)
# define RBIMPL_HAS_BUILTIN___builtin_unreachable       RBIMPL_COMPILER_SINCE(GCC, 4, 5, 0)
# /* Note that "0, 0, 0" might be inaccurate. */

#else
# /* Take config.h definition when available */
# define RBIMPL_HAS_BUILTIN(_) ((RBIMPL_HAS_BUILTIN_ ## _)+0)
# define RBIMPL_HAS_BUILTIN___builtin_add_overflow      HAVE_BUILTIN___BUILTIN_ADD_OVERFLOW
# define RBIMPL_HAS_BUILTIN___builtin_alloca            0
# define RBIMPL_HAS_BUILTIN___builtin_alloca_with_align HAVE_BUILTIN___BUILTIN_ALLOCA_WITH_ALIGN
# define RBIMPL_HAS_BUILTIN___builtin_assume            0
# define RBIMPL_HAS_BUILTIN___builtin_assume_aligned    HAVE_BUILTIN___BUILTIN_ASSUME_ALIGNED
# define RBIMPL_HAS_BUILTIN___builtin_bswap16           HAVE_BUILTIN___BUILTIN_BSWAP16
# define RBIMPL_HAS_BUILTIN___builtin_bswap32           HAVE_BUILTIN___BUILTIN_BSWAP32
# define RBIMPL_HAS_BUILTIN___builtin_bswap64           HAVE_BUILTIN___BUILTIN_BSWAP64
# define RBIMPL_HAS_BUILTIN___builtin_clz               HAVE_BUILTIN___BUILTIN_CLZ
# define RBIMPL_HAS_BUILTIN___builtin_clzl              HAVE_BUILTIN___BUILTIN_CLZL
# define RBIMPL_HAS_BUILTIN___builtin_clzll             HAVE_BUILTIN___BUILTIN_CLZLL
# define RBIMPL_HAS_BUILTIN___builtin_constant_p        HAVE_BUILTIN___BUILTIN_CONSTANT_P
# define RBIMPL_HAS_BUILTIN___builtin_ctz               HAVE_BUILTIN___BUILTIN_CTZ
# define RBIMPL_HAS_BUILTIN___builtin_ctzl              0
# define RBIMPL_HAS_BUILTIN___builtin_ctzll             HAVE_BUILTIN___BUILTIN_CTZLL
# define RBIMPL_HAS_BUILTIN___builtin_expect            HAVE_BUILTIN___BUILTIN_EXPECT
# define RBIMPL_HAS_BUILTIN___builtin_mul_overflow      HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW
# define RBIMPL_HAS_BUILTIN___builtin_mul_overflow_p    HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW_P
# define RBIMPL_HAS_BUILTIN___builtin_popcount          HAVE_BUILTIN___BUILTIN_POPCOUNT
# define RBIMPL_HAS_BUILTIN___builtin_popcountl         0
# define RBIMPL_HAS_BUILTIN___builtin_rotateleft32      0
# define RBIMPL_HAS_BUILTIN___builtin_rotateleft64      0
# define RBIMPL_HAS_BUILTIN___builtin_rotateright32     0
# define RBIMPL_HAS_BUILTIN___builtin_rotateright64     0
# define RBIMPL_HAS_BUILTIN___builtin_popcountll        HAVE_BUILTIN___BUILTIN_POPCOUNTLL
# define RBIMPL_HAS_BUILTIN___builtin_sub_overflow      HAVE_BUILTIN___BUILTIN_SUB_OVERFLOW
# if defined(HAVE___BUILTIN_UNREACHABLE)
#  define RBIMPL_HAS_BUILTIN___builtin_unreachable 1
# else
#  define RBIMPL_HAS_BUILTIN___builtin_unreachable 0
# endif
#endif

#endif /* RBIMPL_HAS_BUILTIN_H */
