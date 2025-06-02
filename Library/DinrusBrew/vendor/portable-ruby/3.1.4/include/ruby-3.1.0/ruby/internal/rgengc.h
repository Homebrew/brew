#ifndef RBIMPL_RGENGC_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RGENGC_H
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
 * @brief      RGENGC write-barrier APIs.
 * @see        Sasada,  K.,  "Gradual  write-barrier   insertion  into  a  Ruby
 *             interpreter",   in  proceedings   of   the   2019  ACM   SIGPLAN
 *             International  Symposium on  Memory Management  (ISMM 2019),  pp
 *             115-121, 2019.  https://doi.org/10.1145/3315573.3329986
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/maybe_unused.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"
#include "ruby/assert.h"

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#undef USE_RGENGC
#define USE_RGENGC 1

/**
 * @private
 *
 * This is  a compile-time flag  to enable/disable incremental GC  feature.  It
 * has to  be set at  the time  ruby itself compiles.   Makes no sense  for 3rd
 * parties.  It is safe  for them to set this though;  that just doesn't change
 * anything.
 */
#ifndef USE_RINCGC
# define USE_RINCGC 1
#endif

/**
 * @deprecated  This macro seems  broken.  Setting this to  anything other than
 *              zero just doesn't compile.  We need to KonMari.
 */
#ifndef USE_RGENGC_LOGGING_WB_UNPROTECT
# define USE_RGENGC_LOGGING_WB_UNPROTECT 0
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RArray.  It has to be set  at the time ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_ARRAY
# define RGENGC_WB_PROTECTED_ARRAY 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RHash.  It has  to be set at the time  ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_HASH
# define RGENGC_WB_PROTECTED_HASH 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RStruct.  It has to be set at the time ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_STRUCT
# define RGENGC_WB_PROTECTED_STRUCT 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RString.  It has to be set at the time ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_STRING
# define RGENGC_WB_PROTECTED_STRING 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RObject.  It has to be set at the time ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_OBJECT
# define RGENGC_WB_PROTECTED_OBJECT 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RRegexp.  It has to be set at the time ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_REGEXP
# define RGENGC_WB_PROTECTED_REGEXP 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RClass.  It has to be set  at the time ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_CLASS
# define RGENGC_WB_PROTECTED_CLASS 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RFloat.  It has to be set  at the time ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_FLOAT
# define RGENGC_WB_PROTECTED_FLOAT 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RComplex.   It has  to be  set at  the time  ruby itself  compiles.
 * Makes no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_COMPLEX
# define RGENGC_WB_PROTECTED_COMPLEX 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RRational.  It  has to  be set  at the  time ruby  itself compiles.
 * Makes no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_RATIONAL
# define RGENGC_WB_PROTECTED_RATIONAL 1
#endif

/**
 * @private
 *
 * This  is   a  compile-time   flag  to   enable/disable  write   barrier  for
 * struct ::RBignum.  It has to be set at the time ruby itself compiles.  Makes
 * no sense for 3rd parties.
 */
#ifndef RGENGC_WB_PROTECTED_BIGNUM
# define RGENGC_WB_PROTECTED_BIGNUM 1
#endif

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 *
 * @internal
 *
 * @shyouhei doesn't think anybody uses this right now.
 */
#ifndef RGENGC_WB_PROTECTED_NODE_CREF
# define RGENGC_WB_PROTECTED_NODE_CREF 1
#endif

/**
 * @defgroup rgengc Write barrier (WB) interfaces:
 *
 * @note The following  core interfaces can  be changed in the  future.  Please
 *       catch up if you want to insert WB into C-extensions correctly.
 *
 * @{
 */

/**
 * Declaration of a "back" pointer.  This  is a write barrier for new reference
 * from  "old"  generation  to  "young" generation.   It  writes  `young`  into
 * `*slot`, which is a pointer inside of `old`.
 *
 * @param[in]   old    An old object.
 * @param[in]   slot   A pointer inside of `old`.
 * @param[out]  young  A young object.
 */
#define RB_OBJ_WRITE(old, slot, young) \
    RBIMPL_CAST(rb_obj_write((VALUE)(old), (VALUE *)(slot), (VALUE)(young), __FILE__, __LINE__))

/**
 * Identical to #RB_OBJ_WRITE(), except it doesn't write any values, but only a
 * WB declaration.   `oldv` is  replaced value  with `b`  (not used  in current
 * Ruby).
 *
 * @param[in]   old    An old object.
 * @param[in]   oldv   An object previously stored inside of `old`.
 * @param[out]  young  A young object.
 */
#define RB_OBJ_WRITTEN(old, oldv, young) \
    RBIMPL_CAST(rb_obj_written((VALUE)(old), (VALUE)(oldv), (VALUE)(young), __FILE__, __LINE__))
/** @} */

#define OBJ_PROMOTED_RAW RB_OBJ_PROMOTED_RAW /**< @old{RB_OBJ_PROMOTED_RAW} */
#define OBJ_PROMOTED     RB_OBJ_PROMOTED     /**< @old{RB_OBJ_PROMOTED} */
#define OBJ_WB_UNPROTECT RB_OBJ_WB_UNPROTECT /**< @old{RB_OBJ_WB_UNPROTECT} */

/**
 * Asserts that the passed object is  not fenced by write barriers.  Objects of
 * such  property do  not contribute  to  generational GCs.   They are  scanned
 * always.
 *
 * @param[out]  x  An object that would not be protected by the barrier.
 */
#define RB_OBJ_WB_UNPROTECT(x) rb_obj_wb_unprotect(x, __FILE__, __LINE__)

/**
 * Identical  to #RB_OBJ_WB_UNPROTECT(),  except it  can also  assert that  the
 * given object is of given type.
 *
 * @param[in]   type  One of `ARRAY`, `STRING`, etc.
 * @param[out]  obj   An object of `type` that would not be protected.
 *
 * @internal
 *
 * @shyouhei doesn't understand why this has to be visible from extensions.
 */
#define RB_OBJ_WB_UNPROTECT_FOR(type, obj) \
    (RGENGC_WB_PROTECTED_##type ? OBJ_WB_UNPROTECT(obj) : obj)

/**
 * @private
 *
 * This is an implementation detail of rb_obj_wb_unprotect().  People don't use
 * it directly.
 */
#define RGENGC_LOGGING_WB_UNPROTECT rb_gc_unprotect_logging

/** @cond INTERNAL_MACRO */
#define RB_OBJ_PROMOTED_RAW RB_OBJ_PROMOTED_RAW
#define RB_OBJ_PROMOTED     RB_OBJ_PROMOTED
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * This  is  the  implementation  of  #RB_OBJ_WRITE().   People  don't  use  it
 * directly.
 *
 * @param[in]   old    An object that points to `young`.
 * @param[out]  young  An object that is referenced from `old`.
 */
void rb_gc_writebarrier(VALUE old, VALUE young);

/**
 * This is the  implementation of #RB_OBJ_WB_UNPROTECT().  People  don't use it
 * directly.
 *
 * @param[out] obj  An object that does not participate in WB.
 */
void rb_gc_writebarrier_unprotect(VALUE obj);

#if USE_RGENGC_LOGGING_WB_UNPROTECT
/**
 * @private
 *
 * This  is  the   implementation  of  #RGENGC_LOGGING_WB_UNPROTECT().   People
 * don't use it directly.
 *
 * @param[in]  objptr    Don't  know why  this  is  a pointer  to  void but  in
 *                       reality this is  a pointer to an object  that is about
 *                       to be un-protected.
 * @param[in]  filename  Pass C's `__FILE__` here.
 * @param[in]  line      Pass C's `__LINE__` here.
 */
void rb_gc_unprotect_logging(void *objptr, const char *filename, int line);
#endif

RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * This  is the  implementation  of #RB_OBJ_PROMOTED().   People  don't use  it
 * directly.
 *
 * @param[in]  obj    An object to query.
 * @retval     true   The object is "promoted".
 * @retval     false  The object is young.  Have not experienced GC at all.
 */
static inline bool
RB_OBJ_PROMOTED_RAW(VALUE obj)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    return RB_FL_ANY_RAW(obj,  RUBY_FL_PROMOTED);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Tests if the object is "promoted" -- that is, whether the object experienced
 * one or more GC marks.
 *
 * @param[in]  obj    An object to query.
 * @retval     true   The object is "promoted".
 * @retval     false  The object is young.  Have not experienced GC at all.
 * @note       Hello, is anyone actively calling this function?  @shyouhei have
 *             never seen  any actual usages  outside of the  GC implementation
 *             itself.
 */
static inline bool
RB_OBJ_PROMOTED(VALUE obj)
{
    if (! RB_FL_ABLE(obj)) {
        return false;
    }
    else {
        return RB_OBJ_PROMOTED_RAW(obj);
    }
}

/**
 * This is the  implementation of #RB_OBJ_WB_UNPROTECT().  People  don't use it
 * directly.
 *
 * @param[out]  x         An object that does not participate in WB.
 * @param[in]   filename  C's `__FILE__` of the caller function.
 * @param[in]   line      C's `__LINE__` of the caller function.
 * @return      x
 */
static inline VALUE
rb_obj_wb_unprotect(
    VALUE x,
    RBIMPL_ATTR_MAYBE_UNUSED()
    const char *filename,
    RBIMPL_ATTR_MAYBE_UNUSED()
    int line)
{
#if USE_RGENGC_LOGGING_WB_UNPROTECT
    RGENGC_LOGGING_WB_UNPROTECT(RBIMPL_CAST((void *)x), filename, line);
#endif
    rb_gc_writebarrier_unprotect(x);
    return x;
}

/**
 * @private
 *
 * This  is  the implementation  of  #RB_OBJ_WRITTEN().   People don't  use  it
 * directly.
 *
 * @param[in]   a         An old object.
 * @param[in]   oldv      An object previously stored inside of `old`.
 * @param[out]  b         A young object.
 * @param[in]   filename  C's `__FILE__` of the caller function.
 * @param[in]   line      C's `__LINE__` of the caller function.
 * @return      a
 */
static inline VALUE
rb_obj_written(
    VALUE a,
    RBIMPL_ATTR_MAYBE_UNUSED()
    VALUE oldv,
    VALUE b,
    RBIMPL_ATTR_MAYBE_UNUSED()
    const char *filename,
    RBIMPL_ATTR_MAYBE_UNUSED()
    int line)
{
#if USE_RGENGC_LOGGING_WB_UNPROTECT
    RGENGC_LOGGING_OBJ_WRITTEN(a, oldv, b, filename, line);
#endif

    if (!RB_SPECIAL_CONST_P(b)) {
        rb_gc_writebarrier(a, b);
    }

    return a;
}

/**
 * @private
 *
 * This  is  the  implementation  of  #RB_OBJ_WRITE().   People  don't  use  it
 * directly.
 *
 * @param[in]   a         An old object.
 * @param[in]   slot      A pointer inside of `old`.
 * @param[out]  b         A young object.
 * @param[in]   filename  C's `__FILE__` of the caller function.
 * @param[in]   line      C's `__LINE__` of the caller function.
 * @return      a
 */
static inline VALUE
rb_obj_write(
    VALUE a, VALUE *slot, VALUE b,
    RBIMPL_ATTR_MAYBE_UNUSED()
    const char *filename,
    RBIMPL_ATTR_MAYBE_UNUSED()
    int line)
{
#ifdef RGENGC_LOGGING_WRITE
    RGENGC_LOGGING_WRITE(a, slot, b, filename, line);
#endif

    *slot = b;

    rb_obj_written(a, RUBY_Qundef /* ignore `oldv' now */, b, filename, line);
    return a;
}

#endif /* RBIMPL_RGENGC_H */
