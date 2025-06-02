#ifndef RUBY_ATOMIC_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_ATOMIC_H
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
 * @brief      Atomic operations
 *
 * Basically, if  we could assume  either C11 or  C++11, these macros  are just
 * redundant.  Sadly we cannot.  We have to do them ourselves.
 */

#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>            /* size_t */
#endif

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>         /* ssize_t */
#endif

#if RBIMPL_COMPILER_SINCE(MSVC, 13, 0, 0)
# pragma intrinsic(_InterlockedOr)
#elif defined(__sun) && defined(HAVE_ATOMIC_H)
# include <atomic.h>
#endif

#include "ruby/assert.h"
#include "ruby/backward/2/limits.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/value.h"
#include "ruby/internal/static_assert.h"
#include "ruby/internal/stdbool.h"

/*
 * Asserts that  your environment supports  more than one atomic  types.  These
 * days systems tend to have such property  (C11 was a standard of decades ago,
 * right?) but we still support older ones.
 */
#if defined(__DOXYGEN__) || defined(HAVE_GCC_ATOMIC_BUILTINS) || defined(HAVE_GCC_SYNC_BUILTINS)
# define RUBY_ATOMIC_GENERIC_MACRO 1
#endif

/**
 * Type  that  is eligible  for  atomic  operations.   Depending on  your  host
 * platform you might have  more than one such type, but we  choose one of them
 * anyways.
 */
#if defined(__DOXYGEN__)
using rb_atomic_t = std::atomic<unsigned>;
#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
typedef unsigned int rb_atomic_t;
#elif defined(HAVE_GCC_SYNC_BUILTINS)
typedef unsigned int rb_atomic_t;
#elif defined(_WIN32)
typedef LONG rb_atomic_t;
#elif defined(__sun) && defined(HAVE_ATOMIC_H)
typedef unsigned int rb_atomic_t;
#else
# error No atomic operation found
#endif

/**
 * Atomically replaces the  value pointed by `var` with the  result of addition
 * of `val` to the old value of `var`.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @param   val  Value to add.
 * @return  What was stored in `var` before the addition.
 * @post    `var` holds `var + val`.
 */
#define RUBY_ATOMIC_FETCH_ADD(var, val) rbimpl_atomic_fetch_add(&(var), (val))

/**
 * Atomically  replaces  the  value  pointed   by  `var`  with  the  result  of
 * subtraction of `val` to the old value of `var`.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @param   val  Value to subtract.
 * @return  What was stored in `var` before the subtraction.
 * @post    `var` holds `var - val`.
 */
#define RUBY_ATOMIC_FETCH_SUB(var, val) rbimpl_atomic_fetch_sub(&(var), (val))

/**
 * Atomically  replaces  the  value  pointed   by  `var`  with  the  result  of
 * bitwise OR between `val` and the old value of `var`.
 *
 * @param   var   A variable of ::rb_atomic_t.
 * @param   val   Value to mix.
 * @return  void
 * @post    `var` holds `var | val`.
 * @note    For portability, this macro can return void.
 */
#define RUBY_ATOMIC_OR(var, val) rbimpl_atomic_or(&(var), (val))

/**
 * Atomically replaces the value pointed by  `var` with `val`.  This is just an
 * assignment, but you can additionally know the previous value.
 *
 * @param   var   A variable of ::rb_atomic_t.
 * @param   val   Value to set.
 * @return  What was stored in `var` before the assignment.
 * @post    `var` holds `val`.
 */
#define RUBY_ATOMIC_EXCHANGE(var, val) rbimpl_atomic_exchange(&(var), (val))

/**
 * Atomic compare-and-swap.   This stores  `val` to  `var` if  and only  if the
 * assignment changes  the value of `var`  from `oldval` to `newval`.   You can
 * detect whether the assignment happened or not using the return value.
 *
 * @param   var        A variable of ::rb_atomic_t.
 * @param   oldval     Expected value of `var` before the assignment.
 * @param   newval     What you want to store at `var`.
 * @retval  oldval     Successful assignment (`var` is now `newval`).
 * @retval  otherwise  Something else is at `var`; not updated.
 */
#define RUBY_ATOMIC_CAS(var, oldval, newval) \
    rbimpl_atomic_cas(&(var), (oldval), (newval))

/**
 * Identical to #RUBY_ATOMIC_EXCHANGE, except for the return type.
 *
 * @param   var   A variable of ::rb_atomic_t.
 * @param   val   Value to set.
 * @return  void
 * @post    `var` holds `val`.
 */
#define RUBY_ATOMIC_SET(var, val) rbimpl_atomic_set(&(var), (val))

/**
 * Identical to #RUBY_ATOMIC_FETCH_ADD, except for the return type.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @param   val  Value to add.
 * @return  void
 * @post    `var` holds `var + val`.
 */
#define RUBY_ATOMIC_ADD(var, val) rbimpl_atomic_add(&(var), (val))

/**
 * Identical to #RUBY_ATOMIC_FETCH_SUB, except for the return type.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @param   val  Value to subtract.
 * @return  void
 * @post    `var` holds `var - val`.
 */
#define RUBY_ATOMIC_SUB(var, val) rbimpl_atomic_sub(&(var), (val))

/**
 * Atomically increments the value pointed by `var`.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @return  void
 * @post    `var` holds `var + 1`.
 */
#define RUBY_ATOMIC_INC(var) rbimpl_atomic_inc(&(var))

/**
 * Atomically decrements the value pointed by `var`.
 *
 * @param   var  A variable of ::rb_atomic_t.
 * @return  void
 * @post    `var` holds `var - 1`.
 */
#define RUBY_ATOMIC_DEC(var) rbimpl_atomic_dec(&(var))

/**
 * Identical to #RUBY_ATOMIC_INC,  except it expects its  argument is `size_t`.
 * There are cases where ::rb_atomic_t is  32bit while `size_t` is 64bit.  This
 * should be used for size related operations to support such platforms.
 *
 * @param   var  A variable of `size_t`.
 * @return  void
 * @post    `var` holds `var + 1`.
 */
#define RUBY_ATOMIC_SIZE_INC(var) rbimpl_atomic_size_inc(&(var))

/**
 * Identical to #RUBY_ATOMIC_DEC,  except it expects its  argument is `size_t`.
 * There are cases where ::rb_atomic_t is  32bit while `size_t` is 64bit.  This
 * should be used for size related operations to support such platforms.
 *
 * @param   var  A variable of `size_t`.
 * @return  void
 * @post    `var` holds `var - 1`.
 */
#define RUBY_ATOMIC_SIZE_DEC(var) rbimpl_atomic_size_dec(&(var))

/**
 * Identical  to #RUBY_ATOMIC_EXCHANGE,  except  it expects  its arguments  are
 * `size_t`.  There  are cases where  ::rb_atomic_t is 32bit while  `size_t` is
 * 64bit.  This  should be  used for  size related  operations to  support such
 * platforms.
 *
 * @param   var  A variable of `size_t`.
 * @param   val   Value to set.
 * @return  What was stored in `var` before the assignment.
 * @post    `var` holds `val`.
 */
#define RUBY_ATOMIC_SIZE_EXCHANGE(var, val) \
    rbimpl_atomic_size_exchange(&(var), (val))

/**
 * Identical to #RUBY_ATOMIC_CAS, except it expects its arguments are `size_t`.
 * There are cases where ::rb_atomic_t is 32bit while `size_t` is 64bit.  This
 * should be used for size related operations to support such platforms.
 *
 * @param   var        A variable of `size_t`.
 * @param   oldval     Expected value of `var` before the assignment.
 * @param   newval     What you want to store at `var`.
 * @retval  oldval     Successful assignment (`var` is now `newval`).
 * @retval  otherwise  Something else is at `var`; not updated.
 */
#define RUBY_ATOMIC_SIZE_CAS(var, oldval, newval) \
    rbimpl_atomic_size_cas(&(var), (oldval), (newval))

/**
 * Identical to #RUBY_ATOMIC_ADD, except it expects its arguments are `size_t`.
 * There are cases where ::rb_atomic_t is 32bit while `size_t` is 64bit.  This
 * should be used for size related operations to support such platforms.
 *
 * @param   var  A variable of `size_t`.
 * @param   val  Value to add.
 * @return  void
 * @post    `var` holds `var + val`.
 */
#define RUBY_ATOMIC_SIZE_ADD(var, val) rbimpl_atomic_size_add(&(var), (val))

/**
 * Identical to #RUBY_ATOMIC_SUB, except it expects its arguments are `size_t`.
 * There are cases where ::rb_atomic_t is 32bit while `size_t` is 64bit.  This
 * should be used for size related operations to support such platforms.
 *
 * @param   var  A variable of `size_t`.
 * @param   val  Value to subtract.
 * @return  void
 * @post    `var` holds `var - val`.
 */
#define RUBY_ATOMIC_SIZE_SUB(var, val) rbimpl_atomic_size_sub(&(var), (val))

/**
 * Identical  to #RUBY_ATOMIC_EXCHANGE,  except  it expects  its arguments  are
 * `void*`.   There are  cases where  ::rb_atomic_t is  32bit while  `void*` is
 * 64bit.  This should  be used for pointer related operations  to support such
 * platforms.
 *
 * @param   var  A variable of `void *`.
 * @param   val   Value to set.
 * @return  What was stored in `var` before the assignment.
 * @post    `var` holds `val`.
 *
 * @internal
 *
 * :FIXME: this `(void*)` cast is evil!  However `void*` is incompatible with
 * some pointers, most notably function pointers.
 */
#define RUBY_ATOMIC_PTR_EXCHANGE(var, val) \
    RBIMPL_CAST(rbimpl_atomic_ptr_exchange((void **)&(var), (void *)val))

/**
 * Identical to #RUBY_ATOMIC_CAS, except it expects its arguments are `void*`.
 * There are cases where ::rb_atomic_t is 32bit while `void*` is 64bit.  This
 * should be used for size related operations to support such platforms.
 *
 * @param   var        A variable of `void*`.
 * @param   oldval     Expected value of `var` before the assignment.
 * @param   newval     What you want to store at `var`.
 * @retval  oldval     Successful assignment (`var` is now `newval`).
 * @retval  otherwise  Something else is at `var`; not updated.
 */
#define RUBY_ATOMIC_PTR_CAS(var, oldval, newval) \
    RBIMPL_CAST(rbimpl_atomic_ptr_cas((void **)&(var), (oldval), (newval)))

/**
 * Identical  to #RUBY_ATOMIC_EXCHANGE,  except  it expects  its arguments  are
 * ::VALUE.   There are  cases where  ::rb_atomic_t is  32bit while  ::VALUE is
 * 64bit.  This should  be used for pointer related operations  to support such
 * platforms.
 *
 * @param   var  A variable of ::VALUE.
 * @param   val   Value to set.
 * @return  What was stored in `var` before the assignment.
 * @post    `var` holds `val`.
 */
#define RUBY_ATOMIC_VALUE_EXCHANGE(var, val) \
    rbimpl_atomic_value_exchange(&(var), (val))

/**
 * Identical to #RUBY_ATOMIC_CAS, except it  expects its arguments are ::VALUE.
 * There are cases  where ::rb_atomic_t is 32bit while ::VALUE  is 64bit.  This
 * should be used for size related operations to support such platforms.
 *
 * @param   var        A variable of `void*`.
 * @param   oldval     Expected value of `var` before the assignment.
 * @param   newval     What you want to store at `var`.
 * @retval  oldval     Successful assignment (`var` is now `newval`).
 * @retval  otherwise  Something else is at `var`; not updated.
 */
#define RUBY_ATOMIC_VALUE_CAS(var, oldval, newval) \
    rbimpl_atomic_value_cas(&(var), (oldval), (newval))

/** @cond INTERNAL_MACRO */
RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline rb_atomic_t
rbimpl_atomic_fetch_add(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    return __atomic_fetch_add(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    return __sync_fetch_and_add(ptr, val);

#elif defined(_WIN32)
    return InterlockedExchangeAdd(ptr, val);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    /*
     * `atomic_add_int_nv` takes its second argument as `int`!  Meanwhile our
     * `rb_atomic_t` is unsigned.  We cannot pass `val` as-is.  We have to
     * manually check integer overflow.
     */
    RBIMPL_ASSERT_OR_ASSUME(val <= INT_MAX);
    return atomic_add_int_nv(ptr, val) - val;

#else
# error Unsupported platform.
#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_add(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    /*
     * GCC on amd64 is smart enough to detect this `__atomic_add_fetch`'s
     * return value is not used, then compiles it into single `LOCK ADD`
     * instruction.
     */
    __atomic_add_fetch(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    __sync_add_and_fetch(ptr, val);

#elif defined(_WIN32)
    /*
     * `InterlockedExchangeAdd` is `LOCK XADD`.  It seems there also is
     * `_InterlockedAdd` intrinsic in ARM Windows but not for x86?  Sticking to
     * `InterlockedExchangeAdd` for better portability.
     */
    InterlockedExchangeAdd(ptr, val);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    /* Ditto for `atomic_add_int_nv`. */
    RBIMPL_ASSERT_OR_ASSUME(val <= INT_MAX);
    atomic_add_int(ptr, val);

#else
# error Unsupported platform.
#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_size_add(volatile size_t *ptr, size_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    __atomic_add_fetch(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    __sync_add_and_fetch(ptr, val);

#elif defined(_WIN32) && defined(_M_AMD64)
    /* Ditto for `InterlockeExchangedAdd`. */
    InterlockedExchangeAdd64(ptr, val);

#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    /* Ditto for `atomic_add_int_nv`. */
    RBIMPL_ASSERT_OR_ASSUME(val <= LONG_MAX);
    atomic_add_long(ptr, val);

#else
    RBIMPL_STATIC_ASSERT(size_of_rb_atomic_t, sizeof *ptr == sizeof(rb_atomic_t));

    volatile rb_atomic_t *const tmp = RBIMPL_CAST((volatile rb_atomic_t *)ptr);
    rbimpl_atomic_add(tmp, val);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_inc(volatile rb_atomic_t *ptr)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS) || defined(HAVE_GCC_SYNC_BUILTINS)
    rbimpl_atomic_add(ptr, 1);

#elif defined(_WIN32)
    InterlockedIncrement(ptr);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    atomic_inc_uint(ptr);

#else
    rbimpl_atomic_add(ptr, 1);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_size_inc(volatile size_t *ptr)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS) || defined(HAVE_GCC_SYNC_BUILTINS)
    rbimpl_atomic_size_add(ptr, 1);

#elif defined(_WIN32) && defined(_M_AMD64)
    InterlockedIncrement64(ptr);

#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    atomic_inc_ulong(ptr);

#else
    rbimpl_atomic_size_add(ptr, 1);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline rb_atomic_t
rbimpl_atomic_fetch_sub(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    return __atomic_fetch_sub(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    return __sync_fetch_and_sub(ptr, val);

#elif defined(_WIN32)
    /* rb_atomic_t is signed here! Safe to do `-val`. */
    return InterlockedExchangeAdd(ptr, -val);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    /* Ditto for `rbimpl_atomic_fetch_add`. */
    const signed neg = -1;
    RBIMPL_ASSERT_OR_ASSUME(val <= INT_MAX);
    return atomic_add_int_nv(ptr, neg * val) + val;

#else
# error Unsupported platform.
#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_sub(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    __atomic_sub_fetch(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    __sync_sub_and_fetch(ptr, val);

#elif defined(_WIN32)
    InterlockedExchangeAdd(ptr, -val);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    const signed neg = -1;
    RBIMPL_ASSERT_OR_ASSUME(val <= INT_MAX);
    atomic_add_int(ptr, neg * val);

#else
# error Unsupported platform.
#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_size_sub(volatile size_t *ptr, size_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    __atomic_sub_fetch(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    __sync_sub_and_fetch(ptr, val);

#elif defined(_WIN32) && defined(_M_AMD64)
    const ssize_t neg = -1;
    InterlockedExchangeAdd64(ptr, neg * val);

#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    const signed neg = -1;
    RBIMPL_ASSERT_OR_ASSUME(val <= LONG_MAX);
    atomic_add_long(ptr, neg * val);

#else
    RBIMPL_STATIC_ASSERT(size_of_rb_atomic_t, sizeof *ptr == sizeof(rb_atomic_t));

    volatile rb_atomic_t *const tmp = RBIMPL_CAST((volatile rb_atomic_t *)ptr);
    rbimpl_atomic_sub(tmp, val);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_dec(volatile rb_atomic_t *ptr)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS) || defined(HAVE_GCC_SYNC_BUILTINS)
    rbimpl_atomic_sub(ptr, 1);

#elif defined(_WIN32)
    InterlockedDecrement(ptr);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    atomic_dec_uint(ptr);

#else
    rbimpl_atomic_sub(ptr, 1);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_size_dec(volatile size_t *ptr)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS) || defined(HAVE_GCC_SYNC_BUILTINS)
    rbimpl_atomic_size_sub(ptr, 1);

#elif defined(_WIN32) && defined(_M_AMD64)
    InterlockedDecrement64(ptr);

#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    atomic_dec_ulong(ptr);

#else
    rbimpl_atomic_size_sub(ptr, 1);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_or(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    __atomic_or_fetch(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    __sync_or_and_fetch(ptr, val);

#elif RBIMPL_COMPILER_SINCE(MSVC, 13, 0, 0)
    _InterlockedOr(ptr, val);

#elif defined(_WIN32) && defined(__GNUC__)
    /* This was for old MinGW.  Maybe not needed any longer? */
    __asm__(
        "lock\n\t"
        "orl\t%1, %0"
        : "=m"(ptr)
        : "Ir"(val));

#elif defined(_WIN32) && defined(_M_IX86)
    __asm mov eax, ptr;
    __asm mov ecx, val;
    __asm lock or [eax], ecx;

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    atomic_or_uint(ptr, val);

#else
# error Unsupported platform.
#endif
}

/* Nobody uses this but for theoretical backwards compatibility... */
#if RBIMPL_COMPILER_BEFORE(MSVC, 13, 0, 0)
static inline rb_atomic_t
rb_w32_atomic_or(volatile rb_atomic_t *var, rb_atomic_t val)
{
    return rbimpl_atomic_or(var, val);
}
#endif

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline rb_atomic_t
rbimpl_atomic_exchange(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    return __atomic_exchange_n(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    return __sync_lock_test_and_set(ptr, val);

#elif defined(_WIN32)
    return InterlockedExchange(ptr, val);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    return atomic_swap_uint(ptr, val);

#else
# error Unsupported platform.
#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline size_t
rbimpl_atomic_size_exchange(volatile size_t *ptr, size_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    return __atomic_exchange_n(ptr, val, __ATOMIC_SEQ_CST);

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    return __sync_lock_test_and_set(ptr, val);

#elif defined(_WIN32) && defined(_M_AMD64)
    return InterlockedExchange64(ptr, val);

#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    return atomic_swap_ulong(ptr, val);

#else
    RBIMPL_STATIC_ASSERT(size_of_size_t, sizeof *ptr == sizeof(rb_atomic_t));

    volatile rb_atomic_t *const tmp = RBIMPL_CAST((volatile rb_atomic_t *)ptr);
    const rb_atomic_t ret = rbimpl_atomic_exchange(tmp, val);
    return RBIMPL_CAST((size_t)ret);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void *
rbimpl_atomic_ptr_exchange(void *volatile *ptr, const void *val)
{
#if 0

#elif defined(InterlockedExchangePointer)
    /* const_cast */
    PVOID *pptr = RBIMPL_CAST((PVOID *)ptr);
    PVOID pval = RBIMPL_CAST((PVOID)val);
    return InterlockedExchangePointer(pptr, pval);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    return atomic_swap_ptr(ptr, RBIMPL_CAST((void *)val));

#else
    RBIMPL_STATIC_ASSERT(sizeof_voidp, sizeof *ptr == sizeof(size_t));

    const size_t sval = RBIMPL_CAST((size_t)val);
    volatile size_t *const sptr = RBIMPL_CAST((volatile size_t *)ptr);
    const size_t sret = rbimpl_atomic_size_exchange(sptr, sval);
    return RBIMPL_CAST((void *)sret);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline VALUE
rbimpl_atomic_value_exchange(volatile VALUE *ptr, VALUE val)
{
    RBIMPL_STATIC_ASSERT(sizeof_value, sizeof *ptr == sizeof(size_t));

    const size_t sval = RBIMPL_CAST((size_t)val);
    volatile size_t *const sptr = RBIMPL_CAST((volatile size_t *)ptr);
    const size_t sret = rbimpl_atomic_size_exchange(sptr, sval);
    return RBIMPL_CAST((VALUE)sret);
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void
rbimpl_atomic_set(volatile rb_atomic_t *ptr, rb_atomic_t val)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    __atomic_store_n(ptr, val, __ATOMIC_SEQ_CST);

#else
    /* Maybe std::atomic<rb_atomic_t>::store can be faster? */
    rbimpl_atomic_exchange(ptr, val);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline rb_atomic_t
rbimpl_atomic_cas(volatile rb_atomic_t *ptr, rb_atomic_t oldval, rb_atomic_t newval)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    __atomic_compare_exchange_n(
        ptr, &oldval, newval, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return oldval;

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    return __sync_val_compare_and_swap(ptr, oldval, newval);

#elif RBIMPL_COMPILER_SINCE(MSVC, 13, 0, 0)
    return InterlockedCompareExchange(ptr, newval, oldval);

#elif defined(_WIN32)
    PVOID *pptr = RBIMPL_CAST((PVOID *)ptr);
    PVOID pold = RBIMPL_CAST((PVOID)oldval);
    PVOID pnew = RBIMPL_CAST((PVOID)newval);
    PVOID pret = InterlockedCompareExchange(pptr, pnew, pold);
    return RBIMPL_CAST((rb_atomic_t)pret);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    return atomic_cas_uint(ptr, oldval, newval);

#else
# error Unsupported platform.
#endif
}

/* Nobody uses this but for theoretical backwards compatibility... */
#if RBIMPL_COMPILER_BEFORE(MSVC, 13, 0, 0)
static inline rb_atomic_t
rb_w32_atomic_cas(volatile rb_atomic_t *var, rb_atomic_t oldval, rb_atomic_t newval)
{
    return rbimpl_atomic_cas(var, oldval, newval);
}
#endif

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline size_t
rbimpl_atomic_size_cas(volatile size_t *ptr, size_t oldval, size_t newval)
{
#if 0

#elif defined(HAVE_GCC_ATOMIC_BUILTINS)
    __atomic_compare_exchange_n(
        ptr, &oldval, newval, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return oldval;

#elif defined(HAVE_GCC_SYNC_BUILTINS)
    return __sync_val_compare_and_swap(ptr, oldval, newval);

#elif defined(_WIN32) && defined(_M_AMD64)
    return InterlockedCompareExchange64(ptr, newval, oldval);

#elif defined(__sun) && defined(HAVE_ATOMIC_H) && (defined(_LP64) || defined(_I32LPx))
    return atomic_cas_ulong(ptr, oldval, newval);

#else
    RBIMPL_STATIC_ASSERT(size_of_size_t, sizeof *ptr == sizeof(rb_atomic_t));

    volatile rb_atomic_t *tmp = RBIMPL_CAST((volatile rb_atomic_t *)ptr);
    return rbimpl_atomic_cas(tmp, oldval, newval);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline void *
rbimpl_atomic_ptr_cas(void **ptr, const void *oldval, const void *newval)
{
#if 0

#elif defined(InterlockedExchangePointer)
    /* ... Can we say that InterlockedCompareExchangePtr surly exists when
     * InterlockedExchangePointer is defined?  Seems so but...?*/
    PVOID *pptr = RBIMPL_CAST((PVOID *)ptr);
    PVOID pold = RBIMPL_CAST((PVOID)oldval);
    PVOID pnew = RBIMPL_CAST((PVOID)newval);
    return InterlockedCompareExchangePointer(pptr, pnew, pold);

#elif defined(__sun) && defined(HAVE_ATOMIC_H)
    void *pold = RBIMPL_CAST((void *)oldval);
    void *pnew = RBIMPL_CAST((void *)newval);
    return atomic_cas_ptr(ptr, pold, pnew);


#else
    RBIMPL_STATIC_ASSERT(sizeof_voidp, sizeof *ptr == sizeof(size_t));

    const size_t snew = RBIMPL_CAST((size_t)newval);
    const size_t sold = RBIMPL_CAST((size_t)oldval);
    volatile size_t *const sptr = RBIMPL_CAST((volatile size_t *)ptr);
    const size_t sret = rbimpl_atomic_size_cas(sptr, sold, snew);
    return RBIMPL_CAST((void *)sret);

#endif
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
static inline VALUE
rbimpl_atomic_value_cas(volatile VALUE *ptr, VALUE oldval, VALUE newval)
{
    RBIMPL_STATIC_ASSERT(sizeof_value, sizeof *ptr == sizeof(size_t));

    const size_t snew = RBIMPL_CAST((size_t)newval);
    const size_t sold = RBIMPL_CAST((size_t)oldval);
    volatile size_t *const sptr = RBIMPL_CAST((volatile size_t *)ptr);
    const size_t sret = rbimpl_atomic_size_cas(sptr, sold, snew);
    return RBIMPL_CAST((VALUE)sret);
}
/** @endcond */
#endif /* RUBY_ATOMIC_H */
