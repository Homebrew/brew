#ifndef RBIMPL_STDALIGN_H                            /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_STDALIGN_H
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
 * @brief      Defines #RBIMPL_ALIGNAS / #RBIMPL_ALIGNOF
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/internal/compiler_is.h"
#include "ruby/internal/has/attribute.h"
#include "ruby/internal/has/declspec_attribute.h"
#include "ruby/internal/has/feature.h"

/**
 * Wraps (or simulates) `alignas`. This is C++11's `alignas` and is _different_
 * from C11 `_Alignas`.  For instance,
 *
 * ```CXX
 * typedef struct alignas(128) foo { int foo } foo;
 * ```
 *
 * is a valid C++ while
 *
 * ```C
 * typedef struct _Alignas(128) foo { int foo } foo;
 * ```
 *
 * is an invalid C because:
 *
 * - You cannot `struct _Alignas`.
 * - A `typedef` cannot have alignments.
 */
#if defined(__cplusplus) && RBIMPL_HAS_FEATURE(cxx_alignas)
# define RBIMPL_ALIGNAS alignas

#elif defined(__cplusplus) && (__cplusplus >= 201103L)
# define RBIMPL_ALIGNAS alignas

#elif defined(__INTEL_CXX11_MODE__)
# define RBIMPL_ALIGNAS alignas

#elif defined(__GXX_EXPERIMENTAL_CXX0X__)
# define RBIMPL_ALIGNAS alignas

#elif RBIMPL_HAS_DECLSPEC_ATTRIBUTE(align)
# define RBIMPL_ALIGNAS(_) __declspec(align(_))

#elif RBIMPL_HAS_ATTRIBUTE(aligned)
# define RBIMPL_ALIGNAS(_) __attribute__((__aligned__(_)))

#else
# define RBIMPL_ALIGNAS(_) /* void */
#endif

/**
 * Wraps (or simulates) `alignof`.
 *
 * We want C11's `_Alignof`.  However in spite of its clear language, compilers
 * (including GCC  and clang) tend to  have buggy implementations.  We  have to
 * avoid such things to resort to our own version.
 *
 * @see https://gcc.gnu.org/bugzilla/show_bug.cgi?id=52023
 * @see https://gcc.gnu.org/bugzilla/show_bug.cgi?id=69560
 * @see https://bugs.llvm.org/show_bug.cgi?id=26547
 */
#if defined(__DOXYGEN__)
# define RBIMPL_ALIGNOF alignof
#elif defined(__cplusplus)
# /* C++11 `alignof()` can be buggy. */
# /* see: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=69560 */
# /* But don't worry, we can use templates. */
# define RBIMPL_ALIGNOF(T) (static_cast<size_t>(ruby::rbimpl_alignof<T>::value))

namespace ruby {
template<typename T>
struct rbimpl_alignof {
    typedef struct {
        char _;
        T t;
    } type;

    enum {
        value = offsetof(type, t)
    };
};
}

#elif RBIMPL_COMPILER_IS(MSVC)
# /* Windows have no alignment glitch.*/
# define RBIMPL_ALIGNOF __alignof

#elif defined(HAVE__ALIGNOF)
# /* Autoconf detected availability of a sane `_Alignof()`. */
# define RBIMPL_ALIGNOF(T) RB_GNUC_EXTENSION(_Alignof(T))

#else
# /* :BEWARE:  This is  the last  resort.   If your  compiler somehow  supports
#  * querying the alignment of a type,  you definitely should use that instead.
#  * There are 2 known pitfalls for this fallback implementation:
#  *
#  * First, it is either an undefined  behaviour (C) or an explicit error (C++)
#  * to define a  struct inside of `offsetof`.  C compilers  tend to accept such
#  * things, but AFAIK C++ has no room to allow.
#  *
#  * Second, there exist T  such that `struct { char _; T t;  }` is invalid.  A
#  * known example is  when T is a  struct with a flexible  array member.  Such
#  * struct cannot be enclosed into another one.
#  */
# /* see: http://www.open-std.org/jtc1/sc22/wg14/www/docs/n2083.htm */
# /* see: http://www.open-std.org/jtc1/sc22/wg14/www/docs/n2350.htm */
# define RBIMPL_ALIGNOF(T) offsetof(struct { char _; T t; }, t)

#endif

#endif /* RBIMPL_STDALIGN_H */
