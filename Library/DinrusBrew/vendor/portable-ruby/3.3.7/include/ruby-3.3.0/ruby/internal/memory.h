#ifndef RBIMPL_MEMORY_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_MEMORY_H
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
 * @brief      Memory management stuff.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#endif

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#ifdef HAVE_ALLOCA_H
# include <alloca.h>
#endif

#if defined(_MSC_VER) && defined(_WIN64)
# include <intrin.h>
# pragma intrinsic(_umul128)
#endif

#include "ruby/internal/attr/alloc_size.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/attr/restrict.h"
#include "ruby/internal/attr/returns_nonnull.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/has/builtin.h"
#include "ruby/internal/stdalign.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/xmalloc.h"
#include "ruby/backward/2/limits.h"
#include "ruby/backward/2/long_long.h"
#include "ruby/backward/2/assume.h"
#include "ruby/defines.h"

/** @cond INTERNAL_MACRO  */

/* Make alloca work the best possible way.  */
#if defined(alloca)
# /* Take that. */
#elif RBIMPL_HAS_BUILTIN(__builtin_alloca)
# define alloca __builtin_alloca
#elif defined(_AIX)
# pragma alloca
#elif defined(__cplusplus)
extern "C" void *alloca(size_t);
#else
extern void *alloca();
#endif

/** @endcond  */

#if defined(__DOXYGEN__)
/**
 * @private
 *
 * Type that is as twice wider as  size_t.  This is an implementation detail of
 * rb_mul_size_overflow().  People should not use it.   This is not a good name
 * either.
 */
typedef uint128_t DSIZE_T;
#elif defined(HAVE_INT128_T) && SIZEOF_SIZE_T <= 8
# define DSIZE_T uint128_t
#elif SIZEOF_SIZE_T * 2 <= SIZEOF_LONG_LONG
# define DSIZE_T unsigned LONG_LONG
#endif

/**
 * @private
 *
 * Maximum  possible  number  of  bytes  that  #RB_ALLOCV  can  allocate  using
 * `alloca`.  Anything  beyond this  is allocated  using rb_alloc_tmp_buffer().
 * This selection is transparent to users.  People don't have to bother.
 */
#ifdef C_ALLOCA
# define RUBY_ALLOCV_LIMIT 0
#else
# define RUBY_ALLOCV_LIMIT 1024
#endif

/**
 * Prevents premature  destruction of local objects.   Ruby's garbage collector
 * is conservative; it  scans the C level machine stack  as well.  Possible in-
 * use Ruby  objects must  remain visible  on stack, to  be properly  marked as
 * such.  However  contemporary C  compilers do not  interface well  with this.
 * Consider the following example:
 *
 * ```CXX
 * auto s = rb_str_new_cstr(" world");
 * auto sptr = RSTRING_PTR(s);
 * auto t = rb_str_new_cstr("hello,"); // Possible GC invocation
 * auto u = rb_str_cat_cstr(t, sptr);
 *
 * RB_GC_GUARD(s); // ensure `s` (and thus `sptr`) do not get GC-ed
 * ```
 *
 * Here, without the #RB_GC_GUARD, the last use of `s` is _before_ the last use
 * of `sptr`.  Compilers  could thus think `s` and `t`  are allowed to overlap.
 * That would eliminate `s`  from the stack, while `sptr` is  still in use.  If
 * our GC  ran at  that very moment,  `s` gets swept  out, which  also destroys
 * `sptr`.  Boom!  You got a SEGV.
 *
 * In order  to prevent this scenario  #RB_GC_GUARD must be placed  _after_ the
 * last use of `sptr`.  Placing  #RB_GC_GUARD before dereferencing `sptr` would
 * be of no use.
 *
 * #RB_GC_GUARD would  not be  necessary at  all in the  above example  if non-
 * inlined  function  calls are  made  on  the  `s`  variable after  `sptr`  is
 * dereferenced.  Thus, in  the above example, calling  any un-inlined function
 * on `s`  such as `rb_str_modify(s);`  will ensure `s`  stays on the  stack or
 * register to prevent a GC invocation from prematurely freeing it.
 *
 * Using the #RB_GC_GUARD  macro is preferable to using  the `volatile` keyword
 * in C.  #RB_GC_GUARD has the following advantages:
 *
 *  - the intent of the macro use is clear.
 *
 *  - #RB_GC_GUARD only affects its call  site.  OTOH `volatile` generates some
 *    extra code every time the variable is used, hurting optimisation.
 *
 *  - `volatile` implementations  may be  buggy/inconsistent in  some compilers
 *    and   architectures.     #RB_GC_GUARD   is   customisable    for   broken
 *    systems/compilers without negatively affecting other systems.
 *
 *  - C++  since C++20  deprecates  `volatile`.  If  you  write your  extension
 *    library in that language there is no escape but to use this macro.
 *
 * @param  v  A variable of ::VALUE type.
 * @post   `v` is still alive.
 */
#ifdef __GNUC__
#define RB_GC_GUARD(v) \
    (*__extension__ ({ \
        volatile VALUE *rb_gc_guarded_ptr = &(v); \
        __asm__("" : : "m"(rb_gc_guarded_ptr)); \
        rb_gc_guarded_ptr; \
    }))
#elif defined _MSC_VER
#define RB_GC_GUARD(v) (*rb_gc_guarded_ptr(&(v)))
#else
#define HAVE_RB_GC_GUARDED_PTR_VAL 1
#define RB_GC_GUARD(v) (*rb_gc_guarded_ptr_val(&(v),(v)))
#endif

/* Casts needed because void* is NOT compatible with others in C++. */

/**
 * Convenient macro that allocates an array of n elements.
 *
 * @param      type            Type of array elements.
 * @param      n               Length of the array.
 * @exception  rb_eNoMemError  No space left for allocation.
 * @exception  rb_eArgError    Integer overflow trying  to calculate the length
 *                             of continuous  memory region of `n`  elements of
 *                             `type`.
 * @return     Storage  instance  that  is  capable of  storing  at  least  `n`
 *             elements of type `type`.
 * @note       It doesn't return NULL, even when `n` is zero.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
#define RB_ALLOC_N(type,n)  RBIMPL_CAST((type *)ruby_xmalloc2((n), sizeof(type)))

/**
 * Shorthand of #RB_ALLOC_N with `n=1`.
 *
 * @param      type            Type of allocation.
 * @exception  rb_eNoMemError  No space left for allocation.
 * @return     Storage instance that can hold an `type` object.
 * @note       It doesn't return NULL.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
#define RB_ALLOC(type)      RBIMPL_CAST((type *)ruby_xmalloc(sizeof(type)))

/**
 * Identical to  #RB_ALLOC_N() but also  nullifies the allocated  region before
 * returning.
 *
 * @param      type            Type of array elements.
 * @param      n               Length of the array.
 * @exception  rb_eNoMemError  No space left for allocation.
 * @exception  rb_eArgError    Integer overflow trying  to calculate the length
 *                             of continuous  memory region of `n`  elements of
 *                             `type`.
 * @return     Storage  instance  that  is  capable of  storing  at  least  `n`
 *             elements of type `type`.
 * @post       Returned array is filled with zeros.
 * @note       It doesn't return NULL, even when `n` is zero.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
#define RB_ZALLOC_N(type,n) RBIMPL_CAST((type *)ruby_xcalloc((n), sizeof(type)))

/**
 * Shorthand of #RB_ZALLOC_N with `n=1`.
 *
 * @param      type            Type of allocation.
 * @exception  rb_eNoMemError  No space left for allocation.
 * @return     Storage instance that can hold an `type` object.
 * @post       Returned object is filled with zeros.
 * @note       It doesn't return NULL.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
#define RB_ZALLOC(type)     (RB_ZALLOC_N(type, 1))

/**
 * Convenient macro that reallocates an array with a new size.
 *
 * @param      var             A variable of `type`,  which points to a storage
 *                             instance  that  was   previously  returned  from
 *                             either
 *                               - ruby_xmalloc(),
 *                               - ruby_xmalloc2(),
 *                               - ruby_xcalloc(),
 *                               - ruby_xrealloc(), or
 *                               - ruby_xrealloc2().
 * @param      type            Type of allocation.
 * @param      n               Requested new size of each element.
 * @exception  rb_eNoMemError  No space left for  allocation.
 * @exception  rb_eArgError    Integer overflow trying  to calculate the length
 *                             of continuous  memory region of `n`  elements of
 *                             `type`.
 * @return     Storage  instance  that  is  capable of  storing  at  least  `n`
 *             elements of type `type`.
 * @pre        The passed variable must point to a valid live storage instance.
 *             It is a  failure to pass a variable that  holds an already-freed
 *             pointer.
 * @note       It doesn't return NULL, even when `n` is zero.
 * @warning    Do not  assume anything  on the alignment  of the  return value.
 *             There is  no guarantee  that it  inherits the  passed argument's
 *             one.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
#define RB_REALLOC_N(var,type,n) \
    ((var) = RBIMPL_CAST((type *)ruby_xrealloc2((void *)(var), (n), sizeof(type))))

/**
 * @deprecated  This  macro is  dangerous (does  not bother  stack overflow  at
 *              all).  #RB_ALLOCV is the modern way to do the same thing.
 * @param       type  Type of array elements.
 * @param       n     Length of the array.
 * @return      A pointer on stack.
 */
#define ALLOCA_N(type,n) \
    RBIMPL_CAST((type *)alloca(rbimpl_size_mul_or_raise(sizeof(type), (n))))

/**
 * Identical to #RB_ALLOCV_N(), except that it allocates a number of bytes and
 * returns a void* .
 *
 * @param   v  A variable to hold the just-in-case opaque Ruby object.
 * @param   n  Size of allocation, in bytes.
 * @return  A void pointer to `n` bytes storage.
 * @note    `n` may be evaluated twice.
 */
#define RB_ALLOCV(v, n)        \
    ((n) < RUBY_ALLOCV_LIMIT ? \
     ((v) = 0, alloca(n)) :    \
     rb_alloc_tmp_buffer(&(v), (n)))

/**
 * Allocates a  memory region, possibly  on stack.   If the given  size exceeds
 * #RUBY_ALLOCV_LIMIT, it allocates a dedicated  opaque ruby object instead and
 * let our GC sweep that region after use.  Either way you can fire-and-forget.
 *
 * ```CXX
 * #include <sys/types.h>
 *
 * VALUE
 * foo(int n)
 * {
 *     VALUE v;
 *     auto ptr = RB_ALLOCV(struct tms, v, n);
 *     ...
 *     // no need to free `ptr`.
 * }
 * ```
 *
 * If you want to  be super-duper polite you can also  explicitly state the end
 * of use of such memory region by calling #RB_ALLOCV_END().
 *
 * @param   type  The type of array elements.
 * @param   v     A variable to hold the just-in-case opaque Ruby object.
 * @param   n     Number of elements requested to allocate.
 * @return  An array of `n` elements of `type`.
 * @note    `n` may be evaluated twice.
 */
#define RB_ALLOCV_N(type, v, n)                             \
    RBIMPL_CAST((type *)                                     \
        (((size_t)(n) < RUBY_ALLOCV_LIMIT / sizeof(type)) ? \
         ((v) = 0, alloca((n) * sizeof(type))) :            \
         rb_alloc_tmp_buffer2(&(v), (n), sizeof(type))))

/**
 * Polite way to declare that the given  array is not used any longer.  Calling
 * this not mandatory.  Our GC can baby-sit  you.  However it is not a very bad
 * idea to use it when possible.  Doing so could reduce memory footprint.
 *
 * @param  v  A variable previously passed to either #RB_ALLOCV/#RB_ALLOCV_N.
 */
#define RB_ALLOCV_END(v) rb_free_tmp_buffer(&(v))

/**
 * Handy macro to erase a region of memory.
 *
 * @param   p     Target pointer.
 * @param   type  Type of `p[0]`
 * @param   n     Length of `p`.
 * @return  `p`.
 * @post    First `n` elements of `p` are squashed.
 */
#define MEMZERO(p,type,n) memset((p), 0, rbimpl_size_mul_or_raise(sizeof(type), (n)))

/**
 * Handy macro to call memcpy.
 *
 * @param   p1    Destination pointer.
 * @param   p2    Source pointer.
 * @param   type  Type of `p2[0]`
 * @param   n     Length of `p2`.
 * @return  `p1`.
 * @post    First `n` elements of `p2` are copied into `p1`.
 */
#define MEMCPY(p1,p2,type,n) ruby_nonempty_memcpy((p1), (p2), rbimpl_size_mul_or_raise(sizeof(type), (n)))

/**
 * Handy macro to call memmove.
 *
 * @param  p1    Destination pointer.
 * @param  p2    Source pointer.
 * @param  type  Type of `p2[0]`
 * @param  n     Length of `p2`.
 * @return `p1`.
 * @post   First `n` elements of `p2` are copied into `p1`.
 */
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), rbimpl_size_mul_or_raise(sizeof(type), (n)))

/**
 * Handy macro to call memcmp
 *
 * @param   p1    Target LHS.
 * @param   p2    Target RHS.
 * @param   type  Type of `p1[0]`
 * @param   n     Length of `p1`.
 * @retval  <0    `p1` is "less" than `p2`.
 * @retval  0     `p1` is equal to `p2`.
 * @retval  >0    `p1` is "greater" than `p2`.
 */
#define MEMCMP(p1,p2,type,n) memcmp((p1), (p2), rbimpl_size_mul_or_raise(sizeof(type), (n)))

#define ALLOC_N    RB_ALLOC_N    /**< @old{RB_ALLOC_N} */
#define ALLOC      RB_ALLOC      /**< @old{RB_ALLOC} */
#define ZALLOC_N   RB_ZALLOC_N   /**< @old{RB_ZALLOC_N} */
#define ZALLOC     RB_ZALLOC     /**< @old{RB_ZALLOC} */
#define REALLOC_N  RB_REALLOC_N  /**< @old{RB_REALLOC_N} */
#define ALLOCV     RB_ALLOCV     /**< @old{RB_ALLOCV} */
#define ALLOCV_N   RB_ALLOCV_N   /**< @old{RB_ALLOCV_N} */
#define ALLOCV_END RB_ALLOCV_END /**< @old{RB_ALLOCV_END} */

/**
 * @private
 *
 * This is an implementation detail of rbimpl_size_mul_overflow().
 *
 * @internal
 *
 * Expecting  this struct  to be  eliminated  by function  inlinings.  This  is
 * nothing more than std::variant<std::size_t> if  we could use recent C++, but
 * reality is we cannot.
 */
struct rbimpl_size_mul_overflow_tag {
    bool left;                  /**< Whether overflow happened or not. */
    size_t right;               /**< Multiplication result. */
};

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2))
RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is  an implementation  detail of #RB_ALLOCV().   People don't  use this
 * directly.
 *
 * @param[out]  store  Pointer to a variable.
 * @param[in]   len    Requested number of bytes to allocate.
 * @return      Allocated `len` bytes array.
 * @post        `store` holds the corresponding tmp buffer object.
 */
void *rb_alloc_tmp_buffer(volatile VALUE *store, long len);

RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2,3))
RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an  implementation detail of #RB_ALLOCV_N().  People  don't use this
 * directly.
 *
 * @param[out]  store  Pointer to a variable.
 * @param[in]   len    Requested number of bytes to allocate.
 * @param[in]   count  Number of elements in an array.
 * @return      Allocated `len` bytes array.
 * @post        `store` holds the corresponding tmp buffer object.
 *
 * @internal
 *
 * Although  the  meaning  of  `count` variable  is  clear,  @shyouhei  doesn't
 * understand its needs.
 */
void *rb_alloc_tmp_buffer_with_count(volatile VALUE *store, size_t len,size_t count);

/**
 * @private
 *
 * This is an implementation detail of #RB_ALLOCV_END().  People don't use this
 * directly.
 *
 * @param[out]  store  Pointer to a variable.
 * @pre         `store` is a NULL, or a pointer to a tmp buffer object.
 * @post        `*store` is ::RUBY_Qfalse.
 * @post        The object formerly stored in `store` is destroyed.
 */
void rb_free_tmp_buffer(volatile VALUE *store);

RBIMPL_ATTR_NORETURN()
/**
 * @private
 *
 * This is an  implementation detail of #RB_ALLOCV_N().  People  don't use this
 * directly.
 *
 * @param[in]  x             Arbitrary value.
 * @param[in]  y             Arbitrary value.
 * @exception  rb_eArgError  `x` * `y` would integer overflow.
 */
void ruby_malloc_size_overflow(size_t x, size_t y);

#ifdef HAVE_RB_GC_GUARDED_PTR_VAL
volatile VALUE *rb_gc_guarded_ptr_val(volatile VALUE *ptr, VALUE val);
#endif
RBIMPL_SYMBOL_EXPORT_END()

#ifdef _MSC_VER
# pragma optimize("", off)

/**
 * @private
 *
 * This is an  implementation detail of #RB_GC_GUARD().  People  don't use this
 * directly.
 *
 * @param[in]  ptr  A pointer to an on-stack C variable.
 * @return     `ptr` as-is.
 */
static inline volatile VALUE *
rb_gc_guarded_ptr(volatile VALUE *ptr)
{
    return ptr;
}

# pragma optimize("", on)
#endif

/**
 * @deprecated  This   function   was   an   implementation   detail   of   old
 *              #RB_ALLOCV_N().  We no longer  use it.  @shyouhei suspects that
 *              there are  no actual usage now.   However it was not  marked as
 *              private before.  We cannot delete it any longer.
 * @param[in]   a    Arbitrary value.
 * @param[in]   b    Arbitrary value.
 * @param[in]   max  Possible maximum value.
 * @param[out]  c    A pointer to return the computation result.
 * @retval      1    `c` is insane.
 * @retval      0    `c` is sane.
 * @post        `c` holds `a` * `b`, but could be overflowed.
 */
static inline int
rb_mul_size_overflow(size_t a, size_t b, size_t max, size_t *c)
{
#ifdef DSIZE_T
    RB_GNUC_EXTENSION DSIZE_T da, db, c2;
    da = a;
    db = b;
    c2 = da * db;
    if (c2 > max) return 1;
    *c = RBIMPL_CAST((size_t)c2);
#else
    if (b != 0 && a > max / b) return 1;
    *c = a * b;
#endif
    return 0;
}

#if defined(__DOXYGEN__)
RBIMPL_ATTR_CONSTEXPR(CXX14)
#elif RBIMPL_COMPILER_SINCE(GCC, 7, 0, 0)
RBIMPL_ATTR_CONSTEXPR(CXX14) /* https://gcc.gnu.org/bugzilla/show_bug.cgi?id=70507 */
#elif RBIMPL_COMPILER_SINCE(Clang, 7, 0, 0)
RBIMPL_ATTR_CONSTEXPR(CXX14) /* https://bugs.llvm.org/show_bug.cgi?id=37633 */
#endif
RBIMPL_ATTR_CONST()
/**
 * @private
 *
 * This is an  implementation detail of #RB_ALLOCV_N().  People  don't use this
 * directly.
 *
 * @param[in]  x  Arbitrary value.
 * @param[in]  y  Arbitrary value.
 * @return     `{ left, right }`,  where `left` is whether there  is an integer
 *             overflow or not,  and `right` is a  (possibly overflowed) result
 *             of `x` * `y`.
 *
 * @internal
 *
 * This is in fact also an implementation detail of ruby_xmalloc2() etc.
 */
static inline struct rbimpl_size_mul_overflow_tag
rbimpl_size_mul_overflow(size_t x, size_t y)
{
    struct rbimpl_size_mul_overflow_tag ret = { false,  0, };

#if RBIMPL_HAS_BUILTIN(__builtin_mul_overflow)
    ret.left = __builtin_mul_overflow(x, y, &ret.right);

#elif defined(DSIZE_T)
    RB_GNUC_EXTENSION DSIZE_T dx = x;
    RB_GNUC_EXTENSION DSIZE_T dy = y;
    RB_GNUC_EXTENSION DSIZE_T dz = dx * dy;
    ret.left  = dz > SIZE_MAX;
    ret.right = RBIMPL_CAST((size_t)dz);

#elif defined(_MSC_VER) && defined(_WIN64)
    unsigned __int64 dp = 0;
    unsigned __int64 dz = _umul128(x, y, &dp);
    ret.left  = RBIMPL_CAST((bool)dp);
    ret.right = RBIMPL_CAST((size_t)dz);

#else
    /* https://wiki.sei.cmu.edu/confluence/display/c/INT30-C.+Ensure+that+unsigned+integer+operations+do+not+wrap */
    ret.left  = (y != 0) && (x > SIZE_MAX / y);
    ret.right = x * y;
#endif

    return ret;
}

/**
 * @private
 *
 * This is an  implementation detail of #RB_ALLOCV_N().  People  don't use this
 * directly.
 *
 * @param[in]  x             Arbitrary value.
 * @param[in]  y             Arbitrary value.
 * @exception  rb_eArgError  Multiplication could integer overflow.
 * @return     `x` * `y`.
 *
 * @internal
 *
 * This is in fact also an implementation detail of ruby_xmalloc2() etc.
 */
static inline size_t
rbimpl_size_mul_or_raise(size_t x, size_t y)
{
    struct rbimpl_size_mul_overflow_tag size =
        rbimpl_size_mul_overflow(x, y);

    if (RB_LIKELY(! size.left)) {
        return size.right;
    }
    else {
        ruby_malloc_size_overflow(x, y);
        RBIMPL_UNREACHABLE_RETURN(0);
    }
}

/**
 * This is an  implementation detail of #RB_ALLOCV_N().  People  don't use this
 * directly.
 *
 * @param[out]  store   Pointer to a variable.
 * @param[in]   count   Number of elements in an array.
 * @param[in]   elsize  Size of each elements.
 * @return      Region of `count` * `elsize` bytes.
 * @post        `store` holds the corresponding tmp buffer object.
 *
 * @internal
 *
 * We might want to deprecate this function and make a `rbimpl_` counterpart.
 */
static inline void *
rb_alloc_tmp_buffer2(volatile VALUE *store, long count, size_t elsize)
{
    const size_t total_size = rbimpl_size_mul_or_raise(count, elsize);
    const size_t cnt = (total_size + sizeof(VALUE) - 1) / sizeof(VALUE);
    return rb_alloc_tmp_buffer_with_count(store, total_size, cnt);
}

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_RETURNS_NONNULL()
/* At least since 2004, glibc's <string.h> annotates memcpy to be
 * __attribute__((__nonnull__(1, 2))).  However it is safe to pass NULL to the
 * source pointer, if n is 0.  Let's wrap memcpy. */
static inline void *
ruby_nonempty_memcpy(void *dest, const void *src, size_t n)
{
    if (n) {
        return memcpy(dest, src, n);
    }
    else {
        return dest;
    }
}
RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_MEMORY_H */
