#ifndef RBIMPL_VALUE_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_VALUE_H
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
 * @brief      Defines ::VALUE and ::ID.
 */
#include "ruby/internal/static_assert.h"
#include "ruby/backward/2/long_long.h"
#include "ruby/backward/2/limits.h"

#if defined(__DOXYGEN__)

/**
 * Type that represents a Ruby object.  It is an unsigned integer of some kind,
 * depending on platforms.
 *
 * ```CXX
 * VALUE value = rb_eval_string("ARGF.readlines.map.with_index");
 * ```
 *
 * @warning  ::VALUE is not a pointer.
 * @warning  ::VALUE can be wider than `long`.
 */
typedef uintptr_t VALUE;

/**
 * Type that represents a Ruby identifier such as a variable name.
 *
 * ```CXX
 * ID method = rb_intern("method");
 * VALUE result = rb_funcall(obj, method, 0);
 * ```
 *
 * @note  ::rb_cSymbol is a Ruby-level data type for the same thing.
 */
typedef uintptr_t ID;

/**
 * A signed integer type that has the same width with ::VALUE.
 *
 * @internal
 *
 * @shyouhei wonders: is it guaranteed  that `uintptr_t` and `intptr_t` are the
 * same width?  As far as I read ISO/IEC 9899:2018 section 7.20.1.4 paragraph 1
 * no such description is given... or defined elsewhere?
 */
typedef intptr_t SIGNED_VALUE;

/**
 * Identical to  `sizeof(VALUE)`, except it  is a macro  that can also  be used
 * inside of preprocessor directives such as `#if`.  Handy on occasions.
 */
#define SIZEOF_VALUE SIZEOF_UINTPTR_T

/**
 * @private
 *
 * A compile-time constant of type ::VALUE whose value is 0.
 */
#define RBIMPL_VALUE_NULL UINTPTR_C(0)

/**
 * @private
 *
 * A compile-time constant of type ::VALUE whose value is 1.
 */
#define RBIMPL_VALUE_ONE  UINTPTR_C(1)

/**
 * @private
 *
 * Maximum possible value that a ::VALUE can take.
 */
#define RBIMPL_VALUE_FULL UINTPTR_MAX

#elif defined HAVE_UINTPTR_T && 0
typedef uintptr_t VALUE;
typedef uintptr_t ID;
# define SIGNED_VALUE intptr_t
# define SIZEOF_VALUE SIZEOF_UINTPTR_T
# undef PRI_VALUE_PREFIX
# define RBIMPL_VALUE_NULL UINTPTR_C(0)
# define RBIMPL_VALUE_ONE  UINTPTR_C(1)
# define RBIMPL_VALUE_FULL UINTPTR_MAX

#elif SIZEOF_LONG == SIZEOF_VOIDP
typedef unsigned long VALUE;
typedef unsigned long ID;
# define SIGNED_VALUE long
# define SIZEOF_VALUE SIZEOF_LONG
# define PRI_VALUE_PREFIX "l"
# define RBIMPL_VALUE_NULL 0UL
# define RBIMPL_VALUE_ONE  1UL
# define RBIMPL_VALUE_FULL ULONG_MAX

#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
typedef unsigned LONG_LONG VALUE;
typedef unsigned LONG_LONG ID;
# define SIGNED_VALUE LONG_LONG
# define LONG_LONG_VALUE 1
# define SIZEOF_VALUE SIZEOF_LONG_LONG
# define PRI_VALUE_PREFIX PRI_LL_PREFIX
# define RBIMPL_VALUE_NULL 0ULL
# define RBIMPL_VALUE_ONE  1ULL
# define RBIMPL_VALUE_FULL ULLONG_MAX

#else
# error ---->> ruby requires sizeof(void*) == sizeof(long) or sizeof(LONG_LONG) to be compiled. <<----
#endif

/** @cond INTERNAL_MACRO */
RBIMPL_STATIC_ASSERT(sizeof_int, SIZEOF_INT == sizeof(int));
RBIMPL_STATIC_ASSERT(sizeof_long, SIZEOF_LONG == sizeof(long));
RBIMPL_STATIC_ASSERT(sizeof_long_long, SIZEOF_LONG_LONG == sizeof(LONG_LONG));
RBIMPL_STATIC_ASSERT(sizeof_voidp, SIZEOF_VOIDP == sizeof(void *));
/** @endcond */
#endif /* RBIMPL_VALUE_H */
