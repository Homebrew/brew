#ifndef RBIMPL_CONFIG_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_CONFIG_H
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
 * @brief      Thin wrapper to ruby/config.h
 */
#include "ruby/config.h"

#ifdef RUBY_EXTCONF_H
# include RUBY_EXTCONF_H
#endif

#include "ruby/internal/compiler_since.h"

#undef  HAVE_PROTOTYPES
#define HAVE_PROTOTYPES 1

#undef  HAVE_STDARG_PROTOTYPES
#define HAVE_STDARG_PROTOTYPES 1

#undef  TOKEN_PASTE
#define TOKEN_PASTE(x,y) x##y

#if defined(__cplusplus)
#/* __builtin_choose_expr and __builtin_types_compatible aren't available
# * on C++.  See https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html */
# undef HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P
# undef HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P

/* HAVE_VA_ARGS_MACRO is for C.  C++ situations might be different. */
# undef HAVE_VA_ARGS_MACRO
# if __cplusplus >= 201103L
#  define HAVE_VA_ARGS_MACRO
# elif defined(__GXX_EXPERIMENTAL_CXX0X__) && __GXX_EXPERIMENTAL_CXX0X__
#  define HAVE_VA_ARGS_MACRO
# elif defined(__INTEL_CXX11_MODE__)
#  define HAVE_VA_ARGS_MACRO
# elif RBIMPL_COMPILER_SINCE(MSVC, 16, 0, 0)
#  define HAVE_VA_ARGS_MACRO
# else
#  /* NG, not known. */
# endif
#endif

#if RBIMPL_COMPILER_BEFORE(GCC, 4, 9, 0)
# /* See https://bugs.ruby-lang.org/issues/14221 */
# undef HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P
#endif

#if RBIMPL_COMPILER_BEFORE(GCC, 5, 0, 0)
# /* GCC 4.9.2 reportedly has this feature  and is broken.  The function is not
#  * officially documented below.  Seems we should not use it.
#  * https://gcc.gnu.org/onlinedocs/gcc-4.9.4/gcc/Other-Builtins.html */
# undef HAVE_BUILTIN___BUILTIN_ALLOCA_WITH_ALIGN
#endif

#if defined(__SUNPRO_CC)
# /* Oracle  Developer Studio  12.5: GCC compatibility guide  says it  supports
#  * statement expressions.   But to our  knowledge they support  the extension
#  * only for C and not for C++.  Prove  me wrong.  Am happy to support them if
#  * there is a way. */
# undef HAVE_STMT_AND_DECL_IN_EXPR
#endif

#ifndef STRINGIZE0
# define STRINGIZE(expr) STRINGIZE0(expr)
# define STRINGIZE0(expr) #expr
#endif

#ifdef AC_APPLE_UNIVERSAL_BUILD
# undef WORDS_BIGENDIAN
# ifdef __BIG_ENDIAN__
#  define WORDS_BIGENDIAN
# endif
#endif

#ifndef DLEXT_MAXLEN
# define DLEXT_MAXLEN 4
#endif

#ifndef RUBY_PLATFORM
# define RUBY_PLATFORM "unknown-unknown"
#endif

#ifdef UNALIGNED_WORD_ACCESS
# /* Take that. */
#elif defined(__i386)
# define UNALIGNED_WORD_ACCESS 1
#elif defined(__i386__)
# define UNALIGNED_WORD_ACCESS 1
#elif defined(_M_IX86)
# define UNALIGNED_WORD_ACCESS 1
#elif defined(__x86_64)
# define UNALIGNED_WORD_ACCESS 1
#elif defined(__x86_64__)
# define UNALIGNED_WORD_ACCESS 1
#elif defined(_M_AMD64)
# define UNALIGNED_WORD_ACCESS 1
#elif defined(__powerpc64__)
# define UNALIGNED_WORD_ACCESS 1
#elif defined(__POWERPC__) // __POWERPC__ is defined for ppc and ppc64 on Darwin
# define UNALIGNED_WORD_ACCESS 1
#elif defined(__aarch64__)
# define UNALIGNED_WORD_ACCESS 1
#elif defined(__mc68020__)
# define UNALIGNED_WORD_ACCESS 1
#else
# define UNALIGNED_WORD_ACCESS 0
#endif

/* Detection of __VA_OPT__ */
#if ! defined(HAVE_VA_ARGS_MACRO)
# undef HAVE___VA_OPT__

#elif defined(__cplusplus)
# if __cplusplus > 201703L
#  define HAVE___VA_OPT__
# else
#  undef HAVE___VA_OPT__
# endif
#else
# /* Idea taken from: https://stackoverflow.com/a/48045656 */
# define RBIMPL_TEST3(q, w, e, ...) e
# define RBIMPL_TEST2(...)          RBIMPL_TEST3(__VA_OPT__(,),1,0,0)
# define RBIMPL_TEST1()             RBIMPL_TEST2("ruby")
# if RBIMPL_TEST1()
#  define HAVE___VA_OPT__
# else
#  undef HAVE___VA_OPT__
# endif
# undef RBIMPL_TEST1
# undef RBIMPL_TEST2
# undef RBIMPL_TEST3
#endif /* HAVE_VA_ARGS_MACRO */

#endif /* RBIMPL_CONFIG_H */
