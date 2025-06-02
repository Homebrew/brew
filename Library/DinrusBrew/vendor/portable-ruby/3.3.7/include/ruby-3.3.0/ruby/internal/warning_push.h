#ifndef RBIMPL_WARNING_PUSH_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_WARNING_PUSH_H
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
 * @brief      Defines #RBIMPL_WARNING_PUSH.
 *
 * ### Q&A ###
 *
 * Q: Why all the macros defined in this file are function-like macros?
 *
 * A: Sigh.   This  is  because of  Doxygen.  Its  `SKIP_FUNCTION_MACROS = YES`
 *    configuration setting  requests us  that if  we want  it to  ignore these
 *    macros,  then we  have to  do  two things:  (1)  let them  be defined  as
 *    function-like macros,  and (2) place  them separately in their  own line,
 *    like below:
 *
 *    ```CXX
 *    // NG -- foo's type  considered something like `unsigned int`.
 *    RBIMPL_WARNING_PUSH
 *    int foo(void);
 *    RBIMPL_WARNING_POP
 *
 *    // OK -- the macros are ignored by Doxygen.
 *    RBIMPL_WARNING_PUSH()
 *    int foo(void);
 *    RBIMPL_WARNING_POP()
 *    ```
 */
#include "ruby/internal/compiler_is.h"
#include "ruby/internal/compiler_since.h"

#if defined(__DOXYGEN__)

/**
 * @private
 *
 * Pushes compiler warning state.
 */
#define RBIMPL_WARNING_PUSH()        __pragma(warning(push))

/**
 * @private
 *
 * Pops compiler warning state.
 */
#define RBIMPL_WARNING_POP()         __pragma(warning(pop))

/**
 * @private
 *
 * Turns a warning into a fatal error.
 *
 * @param  flag  A flag that represents the kind of warnings.
 */
#define RBIMPL_WARNING_ERROR(flag)   __pragma(warning(error: flag))

/**
 * @private
 *
 * Suppresses a warning.
 *
 * @param  flag  A flag that represents the kind of warnings.
 */
#define RBIMPL_WARNING_IGNORED(flag) __pragma(warning(disable: flag))

#elif RBIMPL_COMPILER_SINCE(MSVC, 12, 0, 0)
# /* Not sure exactly when but it seems VC++ 6.0 is a version with it.*/
# define RBIMPL_WARNING_PUSH()        __pragma(warning(push))
# define RBIMPL_WARNING_POP()         __pragma(warning(pop))
# define RBIMPL_WARNING_ERROR(flag)   __pragma(warning(error: flag))
# define RBIMPL_WARNING_IGNORED(flag) __pragma(warning(disable: flag))

#elif RBIMPL_COMPILER_SINCE(Intel, 13, 0, 0)
# define RBIMPL_WARNING_PUSH()        __pragma(warning(push))
# define RBIMPL_WARNING_POP()         __pragma(warning(pop))
# define RBIMPL_WARNING_ERROR(flag)   __pragma(warning(error: flag))
# define RBIMPL_WARNING_IGNORED(flag) __pragma(warning(disable: flag))

#elif RBIMPL_COMPILER_IS(Clang) || RBIMPL_COMPILER_IS(Apple)
# /* Not sure exactly when but it seems LLVM 2.6.0 is a version with it. */
# define RBIMPL_WARNING_PRAGMA0(x)    _Pragma(# x)
# define RBIMPL_WARNING_PRAGMA1(x)    RBIMPL_WARNING_PRAGMA0(clang diagnostic x)
# define RBIMPL_WARNING_PRAGMA2(x, y) RBIMPL_WARNING_PRAGMA1(x # y)
# define RBIMPL_WARNING_PUSH()        RBIMPL_WARNING_PRAGMA1(push)
# define RBIMPL_WARNING_POP()         RBIMPL_WARNING_PRAGMA1(pop)
# define RBIMPL_WARNING_ERROR(flag)   RBIMPL_WARNING_PRAGMA2(error, flag)
# define RBIMPL_WARNING_IGNORED(flag) RBIMPL_WARNING_PRAGMA2(ignored, flag)

#elif RBIMPL_COMPILER_SINCE(GCC, 4, 6, 0)
# /* https://gcc.gnu.org/onlinedocs/gcc-4.6.0/gcc/Diagnostic-Pragmas.html */
# define RBIMPL_WARNING_PRAGMA0(x)    _Pragma(# x)
# define RBIMPL_WARNING_PRAGMA1(x)    RBIMPL_WARNING_PRAGMA0(GCC diagnostic x)
# define RBIMPL_WARNING_PRAGMA2(x, y) RBIMPL_WARNING_PRAGMA1(x # y)
# define RBIMPL_WARNING_PUSH()        RBIMPL_WARNING_PRAGMA1(push)
# define RBIMPL_WARNING_POP()         RBIMPL_WARNING_PRAGMA1(pop)
# define RBIMPL_WARNING_ERROR(flag)   RBIMPL_WARNING_PRAGMA2(error, flag)
# define RBIMPL_WARNING_IGNORED(flag) RBIMPL_WARNING_PRAGMA2(ignored, flag)

#else
# /* :FIXME: improve here */
# define RBIMPL_WARNING_PUSH()        /* void */
# define RBIMPL_WARNING_POP()         /* void */
# define RBIMPL_WARNING_ERROR(flag)   /* void */
# define RBIMPL_WARNING_IGNORED(flag) /* void */
#endif /* _MSC_VER */
/** @endcond */

#endif /* RBIMPL_WARNING_PUSH_H */
