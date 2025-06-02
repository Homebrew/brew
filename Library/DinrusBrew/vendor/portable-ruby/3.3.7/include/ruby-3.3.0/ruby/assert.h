#ifndef RUBY_ASSERT_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_ASSERT_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @date       Wed May 18 00:21:44 JST 1994
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
 */
#include "ruby/internal/assume.h"
#include "ruby/internal/attr/cold.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/dllexport.h"
#include "ruby/backward/2/assume.h"

/* RUBY_NDEBUG  is very  simple:  after everything  described  below are  done,
 * define it with either NDEBUG is undefined (=0) or defined (=1).  It is truly
 * subordinate.
 *
 * RUBY_DEBUG versus NDEBUG is complicated.  Assertions shall be:
 *
 *                      | -UNDEBUG | -DNDEBUG
 *       ---------------+----------+---------
 *       -URUBY_DEBUG   | (*1)     | disabled
 *       -DRUBY_DEBUG=0 | disabled | disabled
 *       -DRUBY_DEBUG=1 | enabled  | (*2)
 *       -DRUBY_DEBUG   | enabled  | (*2)
 *
 * where:
 *
 *   - (*1): Assertions shall  be silently disabled, no warnings,  in favour of
 *     commit 21991e6ca59274e41a472b5256bd3245f6596c90.
 *
 *   - (*2): Compile-time warnings shall be issued.
 */

/** @cond INTERNAL_MACRO */

/*
 * Pro tip: `!!RUBY_DEBUG-1` expands to...
 *
 * - `!!(-1)`  (== `!0`  ==  `1`) when RUBY_DEBUG is defined to be empty,
 * - `(!!0)-1` (== `0-1` == `-1`) when RUBY_DEBUG is defined as 0, and
 * - `(!!n)-1` (== `1-1` ==  `0`) when RUBY_DEBUG is defined as something else.
 */
#if ! defined(RUBY_DEBUG)
# define RBIMPL_RUBY_DEBUG 0
#elif !!RUBY_DEBUG-1 < 0
# define RBIMPL_RUBY_DEBUG 0
#else
# define RBIMPL_RUBY_DEBUG 1
#endif

/*
 * ISO/IEC 9899 (all past versions) says that  "If NDEBUG is defined as a macro
 * name at  the point  in the  source file where  <assert.h> is  included, ..."
 * which means we must not take its defined value into account.
 */
#if defined(NDEBUG)
# define RBIMPL_NDEBUG 1
#else
# define RBIMPL_NDEBUG 0
#endif

/** @endcond */

/* Here we go... */
#undef RUBY_DEBUG
#undef RUBY_NDEBUG
#undef NDEBUG
#if defined(__DOXYGEN__)
# /** Define this macro when you want assertions. */
# define RUBY_DEBUG 0
# /** Define this macro when you don't want assertions. */
# define NDEBUG
# /** This macro is basically the same as #NDEBUG */
# define RUBY_NDEBUG 1

#elif (RBIMPL_NDEBUG == 1) && (RBIMPL_RUBY_DEBUG == 0)
# /* Assertions disabled as per request, no conflicts. */
# define RUBY_DEBUG 0
# define RUBY_NDEBUG 1
# define NDEBUG

#elif (RBIMPL_NDEBUG == 0) && (RBIMPL_RUBY_DEBUG == 1)
# /* Assertions enabled as per request, no conflicts. */
# define RUBY_DEBUG 1
# define RUBY_NDEBUG 0
# /* keep NDEBUG undefined */

#elif (RBIMPL_NDEBUG == 0) && (RBIMPL_RUBY_DEBUG == 0)
# /* The (*1) situation in above diagram. */
# define RUBY_DEBUG 0
# define RUBY_NDEBUG 1
# define NDEBUG

#elif (RBIMPL_NDEBUG == 1) && (RBIMPL_RUBY_DEBUG == 1)
# /* The (*2) situation in above diagram. */
# define RUBY_DEBUG 1
# define RUBY_NDEBUG 0
# /* keep NDEBUG undefined */

# if defined(_MSC_VER)
#  pragma message("NDEBUG is ignored because RUBY_DEBUG>0.")
# elif defined(__GNUC__)
#  pragma GCC warning "NDEBUG is ignored because RUBY_DEBUG>0."
# else
#  error NDEBUG is ignored because RUBY_DEBUG>0.
# endif
#endif
#undef RBIMPL_NDEBUG
#undef RBIMPL_RUBY_DEBUG

/** @cond INTERNAL_MACRO */
#define RBIMPL_ASSERT_NOTHING RBIMPL_CAST((void)0)

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_COLD()
void rb_assert_failure(const char *file, int line, const char *name, const char *expr);
RBIMPL_SYMBOL_EXPORT_END()

#ifdef RUBY_FUNCTION_NAME_STRING
# define RBIMPL_ASSERT_FUNC RUBY_FUNCTION_NAME_STRING
#else
# define RBIMPL_ASSERT_FUNC RBIMPL_CAST((const char *)0)
#endif

/** @endcond */

/**
 * Prints the given message, and terminates the entire process abnormally.
 *
 * @param  mesg  The message to display.
 */
#define RUBY_ASSERT_FAIL(mesg) \
    rb_assert_failure(__FILE__, __LINE__, RBIMPL_ASSERT_FUNC, mesg)

/**
 * Asserts that the expression is truthy.  If not aborts with the message.
 *
 * @param  expr  What supposedly evaluates to true.
 * @param  mesg  The message to display on failure.
 */
#define RUBY_ASSERT_MESG(expr, mesg) \
    (RB_LIKELY(expr) ? RBIMPL_ASSERT_NOTHING : RUBY_ASSERT_FAIL(mesg))

/**
 * A variant of #RUBY_ASSERT that does not interface with #RUBY_DEBUG.
 *
 * @copydetails #RUBY_ASSERT
 */
#define RUBY_ASSERT_ALWAYS(expr) RUBY_ASSERT_MESG((expr), #expr)

/**
 * Asserts that the given expression is truthy if and only if #RUBY_DEBUG is truthy.
 *
 * @param  expr  What supposedly evaluates to true.
 */
#if RUBY_DEBUG
# define RUBY_ASSERT(expr) RUBY_ASSERT_MESG((expr), #expr)
#else
# define RUBY_ASSERT(expr) RBIMPL_ASSERT_NOTHING
#endif

/**
 * A  variant  of   #RUBY_ASSERT  that  interfaces  with   #NDEBUG  instead  of
 * #RUBY_DEBUG.  This almost resembles `assert`  C standard macro, except minor
 * implementation details.
 *
 * @copydetails #RUBY_ASSERT
 */
/* Currently  `RUBY_DEBUG == ! defined(NDEBUG)` is  always true.   There is  no
 * difference any longer between this one and `RUBY_ASSERT`. */
#if defined(NDEBUG)
# define RUBY_ASSERT_NDEBUG(expr) RBIMPL_ASSERT_NOTHING
#else
# define RUBY_ASSERT_NDEBUG(expr) RUBY_ASSERT_MESG((expr), #expr)
#endif

/**
 * @copydoc #RUBY_ASSERT_WHEN
 * @param  mesg  The message to display on failure.
 */
#if RUBY_DEBUG
# define RUBY_ASSERT_MESG_WHEN(cond, expr, mesg) RUBY_ASSERT_MESG((expr), (mesg))
#else
# define RUBY_ASSERT_MESG_WHEN(cond, expr, mesg) \
    ((cond) ? RUBY_ASSERT_MESG((expr), (mesg)) : RBIMPL_ASSERT_NOTHING)
#endif

/**
 * A variant  of #RUBY_ASSERT  that asserts when  either #RUBY_DEBUG  or `cond`
 * parameter is truthy.
 *
 * @param  cond  Extra condition that shall hold for assertion to take effect.
 * @param  expr  What supposedly evaluates to true.
 */
#define RUBY_ASSERT_WHEN(cond, expr) RUBY_ASSERT_MESG_WHEN((cond), (expr), #expr)

/**
 * This is either #RUBY_ASSERT or #RBIMPL_ASSUME, depending on #RUBY_DEBUG.
 *
 * @copydetails #RUBY_ASSERT
 */
#if RUBY_DEBUG
# define RBIMPL_ASSERT_OR_ASSUME(expr) RUBY_ASSERT_ALWAYS(expr)
#elif RBIMPL_COMPILER_BEFORE(Clang, 7, 0, 0)
# /* See commit 67d259c5dccd31fe49d417fec169977712ffdf10 */
# define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSERT_NOTHING
#elif defined(RUBY_ASSERT_NOASSUME)
# /* See commit d300a734414ef6de7e8eb563b7cc4389c455ed08 */
# define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSERT_NOTHING
#elif ! defined(RBIMPL_HAVE___ASSUME)
# define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSERT_NOTHING
#else
# define RBIMPL_ASSERT_OR_ASSUME(expr) RBIMPL_ASSUME(expr)
#endif

#endif /* RUBY_ASSERT_H */
