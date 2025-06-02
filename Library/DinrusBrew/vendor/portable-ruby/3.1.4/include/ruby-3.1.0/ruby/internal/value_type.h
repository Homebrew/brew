#ifndef RBIMPL_VALUE_TYPE_H                          /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_VALUE_TYPE_H
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
 * @brief      Defines enum ::ruby_value_type.
 */
#include "ruby/internal/assume.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/cold.h"
#include "ruby/internal/attr/enum_extensibility.h"
#include "ruby/internal/attr/forceinline.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/constant_p.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/error.h"
#include "ruby/internal/has/builtin.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"
#include "ruby/assert.h"

#if defined(T_DATA)
/*
 * :!BEWARE!: (Recent?)   Solaris' <nfs/nfs.h>  have conflicting  definition of
 * T_DATA.  Let us stop here.  Please have a workaround like this:
 *
 * ```C
 * #include <ruby/ruby.h> // <- Include this one first.
 * #undef T_DATA          // <- ... and stick to RUBY_T_DATA forever.
 * #include <nfs/nfs.h>   // <- OS-provided T_DATA introduced.
 * ```
 *
 * See also [ruby-core:4261]
 */
# error Bail out due to conflicting definition of T_DATA.
#endif

#define T_ARRAY    RUBY_T_ARRAY    /**< @old{RUBY_T_ARRAY} */
#define T_BIGNUM   RUBY_T_BIGNUM   /**< @old{RUBY_T_BIGNUM} */
#define T_CLASS    RUBY_T_CLASS    /**< @old{RUBY_T_CLASS} */
#define T_COMPLEX  RUBY_T_COMPLEX  /**< @old{RUBY_T_COMPLEX} */
#define T_DATA     RUBY_T_DATA     /**< @old{RUBY_T_DATA} */
#define T_FALSE    RUBY_T_FALSE    /**< @old{RUBY_T_FALSE} */
#define T_FILE     RUBY_T_FILE     /**< @old{RUBY_T_FILE} */
#define T_FIXNUM   RUBY_T_FIXNUM   /**< @old{RUBY_T_FIXNUM} */
#define T_FLOAT    RUBY_T_FLOAT    /**< @old{RUBY_T_FLOAT} */
#define T_HASH     RUBY_T_HASH     /**< @old{RUBY_T_HASH} */
#define T_ICLASS   RUBY_T_ICLASS   /**< @old{RUBY_T_ICLASS} */
#define T_IMEMO    RUBY_T_IMEMO    /**< @old{RUBY_T_IMEMO} */
#define T_MASK     RUBY_T_MASK     /**< @old{RUBY_T_MASK} */
#define T_MATCH    RUBY_T_MATCH    /**< @old{RUBY_T_MATCH} */
#define T_MODULE   RUBY_T_MODULE   /**< @old{RUBY_T_MODULE} */
#define T_MOVED    RUBY_T_MOVED    /**< @old{RUBY_T_MOVED} */
#define T_NIL      RUBY_T_NIL      /**< @old{RUBY_T_NIL} */
#define T_NODE     RUBY_T_NODE     /**< @old{RUBY_T_NODE} */
#define T_NONE     RUBY_T_NONE     /**< @old{RUBY_T_NONE} */
#define T_OBJECT   RUBY_T_OBJECT   /**< @old{RUBY_T_OBJECT} */
#define T_RATIONAL RUBY_T_RATIONAL /**< @old{RUBY_T_RATIONAL} */
#define T_REGEXP   RUBY_T_REGEXP   /**< @old{RUBY_T_REGEXP} */
#define T_STRING   RUBY_T_STRING   /**< @old{RUBY_T_STRING} */
#define T_STRUCT   RUBY_T_STRUCT   /**< @old{RUBY_T_STRUCT} */
#define T_SYMBOL   RUBY_T_SYMBOL   /**< @old{RUBY_T_SYMBOL} */
#define T_TRUE     RUBY_T_TRUE     /**< @old{RUBY_T_TRUE} */
#define T_UNDEF    RUBY_T_UNDEF    /**< @old{RUBY_T_UNDEF} */
#define T_ZOMBIE   RUBY_T_ZOMBIE   /**< @old{RUBY_T_ZOMBIE} */

#define BUILTIN_TYPE      RB_BUILTIN_TYPE   /**< @old{RB_BUILTIN_TYPE} */
#define DYNAMIC_SYM_P     RB_DYNAMIC_SYM_P  /**< @old{RB_DYNAMIC_SYM_P} */
#define RB_INTEGER_TYPE_P rb_integer_type_p /**< @old{rb_integer_type_p} */
#define SYMBOL_P          RB_SYMBOL_P       /**< @old{RB_SYMBOL_P} */
#define rb_type_p         RB_TYPE_P         /**< @alias{RB_TYPE_P} */

/** @cond INTERNAL_MACRO */
#define RB_BUILTIN_TYPE   RB_BUILTIN_TYPE
#define RB_DYNAMIC_SYM_P  RB_DYNAMIC_SYM_P
#define RB_FLOAT_TYPE_P   RB_FLOAT_TYPE_P
#define RB_SYMBOL_P       RB_SYMBOL_P
#define RB_TYPE_P         RB_TYPE_P
#define Check_Type        Check_Type

#if !RUBY_DEBUG
# define RBIMPL_ASSERT_TYPE(v, t) RBIMPL_ASSERT_OR_ASSUME(RB_TYPE_P((v), (t)))
#else
# define RBIMPL_ASSERT_TYPE Check_Type
#endif
/** @endcond */

/** @old{rb_type} */
#define TYPE(_)           RBIMPL_CAST((int)rb_type(_))

/** C-level type of an object. */
enum
RBIMPL_ATTR_ENUM_EXTENSIBILITY(closed)
ruby_value_type {
    RUBY_T_NONE     = 0x00, /**< Non-object (swept etc.) */

    RUBY_T_OBJECT   = 0x01, /**< @see struct ::RObject */
    RUBY_T_CLASS    = 0x02, /**< @see struct ::RClass and ::rb_cClass */
    RUBY_T_MODULE   = 0x03, /**< @see struct ::RClass and ::rb_cModule */
    RUBY_T_FLOAT    = 0x04, /**< @see struct ::RFloat */
    RUBY_T_STRING   = 0x05, /**< @see struct ::RString */
    RUBY_T_REGEXP   = 0x06, /**< @see struct ::RRegexp */
    RUBY_T_ARRAY    = 0x07, /**< @see struct ::RArray */
    RUBY_T_HASH     = 0x08, /**< @see struct ::RHash */
    RUBY_T_STRUCT   = 0x09, /**< @see struct ::RStruct */
    RUBY_T_BIGNUM   = 0x0a, /**< @see struct ::RBignum */
    RUBY_T_FILE     = 0x0b, /**< @see struct ::RFile */
    RUBY_T_DATA     = 0x0c, /**< @see struct ::RTypedData */
    RUBY_T_MATCH    = 0x0d, /**< @see struct ::RMatch */
    RUBY_T_COMPLEX  = 0x0e, /**< @see struct ::RComplex */
    RUBY_T_RATIONAL = 0x0f, /**< @see struct ::RRational */

    RUBY_T_NIL      = 0x11, /**< @see ::RUBY_Qnil */
    RUBY_T_TRUE     = 0x12, /**< @see ::RUBY_Qfalse */
    RUBY_T_FALSE    = 0x13, /**< @see ::RUBY_Qtrue */
    RUBY_T_SYMBOL   = 0x14, /**< @see struct ::RSymbol */
    RUBY_T_FIXNUM   = 0x15, /**< Integers formerly known as Fixnums. */
    RUBY_T_UNDEF    = 0x16, /**< @see ::RUBY_Qundef */

    RUBY_T_IMEMO    = 0x1a, /**< @see struct ::RIMemo */
    RUBY_T_NODE     = 0x1b, /**< @see struct ::RNode */
    RUBY_T_ICLASS   = 0x1c, /**< Hidden classes known as IClasses. */
    RUBY_T_ZOMBIE   = 0x1d, /**< @see struct ::RZombie */
    RUBY_T_MOVED    = 0x1e, /**< @see struct ::RMoved */

    RUBY_T_MASK     = 0x1f  /**< Bitmask of ::ruby_value_type. */
};

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_COLD()
/**
 * @private
 *
 * This was  the old implementation  of Check_Type(), but they  diverged.  This
 * one remains  for theoretical backwards compatibility.   People normally need
 * not use it.
 *
 * @param[in]  obj            An object.
 * @param[in]  t              A type.
 * @exception  rb_eTypeError  `obj` is not of type `t`.
 * @exception  rb_eFatal      `obj` is corrupt.
 * @post       Upon successful return `obj` is guaranteed to have type `t`.
 *
 * @internal
 *
 * The second argument shall have been enum ::ruby_value_type.  But at the time
 * matz designed this  function he still used  K&R C.  There was  no such thing
 * like a function prototype.  We can no longer change this API.
 */
void rb_check_type(VALUE obj, int t);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries the type of the object.
 *
 * @param[in]  obj  Object in question.
 * @pre        `obj` must not be a special constant.
 * @return     The type of `obj`.
 */
static inline enum ruby_value_type
RB_BUILTIN_TYPE(VALUE obj)
{
    RBIMPL_ASSERT_OR_ASSUME(! RB_SPECIAL_CONST_P(obj));

#if 0 && defined __GNUC__ && !defined __clang__
    /* Don't move the access to `flags` before the preceding
     * RB_SPECIAL_CONST_P check. */
    __asm volatile("": : :"memory");
#endif
    VALUE ret = RBASIC(obj)->flags & RUBY_T_MASK;
    return RBIMPL_CAST((enum ruby_value_type)ret);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/**
 * Queries if the object is an instance of ::rb_cInteger.
 *
 * @param[in]  obj    Object in question.
 * @retval     true   It is.
 * @retval     false  It isn't.
 */
static inline bool
rb_integer_type_p(VALUE obj)
{
    if (RB_FIXNUM_P(obj)) {
        return true;
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_BIGNUM;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/**
 * Identical to RB_BUILTIN_TYPE(), except it can also accept special constants.
 *
 * @param[in]  obj  Object in question.
 * @return     The type of `obj`.
 */
static inline enum ruby_value_type
rb_type(VALUE obj)
{
    if (! RB_SPECIAL_CONST_P(obj)) {
        return RB_BUILTIN_TYPE(obj);
    }
    else if (obj == RUBY_Qfalse) {
        return RUBY_T_FALSE;
    }
    else if (obj == RUBY_Qnil) {
        return RUBY_T_NIL;
    }
    else if (obj == RUBY_Qtrue) {
        return RUBY_T_TRUE;
    }
    else if (obj == RUBY_Qundef) {
        return RUBY_T_UNDEF;
    }
    else if (RB_FIXNUM_P(obj)) {
        return RUBY_T_FIXNUM;
    }
    else if (RB_STATIC_SYM_P(obj)) {
        return RUBY_T_SYMBOL;
    }
    else {
        RBIMPL_ASSUME(RB_FLONUM_P(obj));
        return RUBY_T_FLOAT;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries if the object is an instance of ::rb_cFloat.
 *
 * @param[in]  obj    Object in question.
 * @retval     true   It is.
 * @retval     false  It isn't.
 */
static inline bool
RB_FLOAT_TYPE_P(VALUE obj)
{
    if (RB_FLONUM_P(obj)) {
        return true;
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_FLOAT;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries if the object is a dynamic symbol.
 *
 * @param[in]  obj    Object in question.
 * @retval     true   It is.
 * @retval     false  It isn't.
 */
static inline bool
RB_DYNAMIC_SYM_P(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_SYMBOL;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries if the object is an instance of ::rb_cSymbol.
 *
 * @param[in]  obj    Object in question.
 * @retval     true   It is.
 * @retval     false  It isn't.
 */
static inline bool
RB_SYMBOL_P(VALUE obj)
{
    return RB_STATIC_SYM_P(obj) || RB_DYNAMIC_SYM_P(obj);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_FORCEINLINE()
/**
 * @private
 *
 * This is an implementation detail of RB_TYPE_P().  Just don't use it.
 *
 * @param[in]  obj    An object.
 * @param[in]  t      A type.
 * @retval     true   `obj` is of type `t`.
 * @retval     false  Otherwise.
 */
static bool
rbimpl_RB_TYPE_P_fastpath(VALUE obj, enum ruby_value_type t)
{
    if (t == RUBY_T_TRUE) {
        return obj == RUBY_Qtrue;
    }
    else if (t == RUBY_T_FALSE) {
        return obj == RUBY_Qfalse;
    }
    else if (t == RUBY_T_NIL) {
        return obj == RUBY_Qnil;
    }
    else if (t == RUBY_T_UNDEF) {
        return obj == RUBY_Qundef;
    }
    else if (t == RUBY_T_FIXNUM) {
        return RB_FIXNUM_P(obj);
    }
    else if (t == RUBY_T_SYMBOL) {
        return RB_SYMBOL_P(obj);
    }
    else if (t == RUBY_T_FLOAT) {
        return RB_FLOAT_TYPE_P(obj);
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else if (t == RB_BUILTIN_TYPE(obj)) {
        return true;
    }
    else {
        return false;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries if the given object is of given type.
 *
 * @param[in]  obj    An object.
 * @param[in]  t      A type.
 * @retval     true   `obj` is of type `t`.
 * @retval     false  Otherwise.
 *
 * @internal
 *
 * This  function is  a super-duper  hot  path.  Optimised  targeting modern  C
 * compilers and x86_64 architecture.
 */
static inline bool
RB_TYPE_P(VALUE obj, enum ruby_value_type t)
{
    if (RBIMPL_CONSTANT_P(t)) {
        return rbimpl_RB_TYPE_P_fastpath(obj, t);
    }
    else {
        return t == rb_type(obj);
    }
}

/** @cond INTERNAL_MACRO */
/* Clang, unlike GCC, cannot propagate __builtin_constant_p beyond function
 * boundary. */
#if defined(__clang__)
# undef RB_TYPE_P
# define RB_TYPE_P(obj, t)                  \
    (RBIMPL_CONSTANT_P(t)                  ? \
     rbimpl_RB_TYPE_P_fastpath((obj), (t)) : \
     (RB_TYPE_P)((obj), (t)))
#endif

/* clang 3.x (4.2 compatible) can't eliminate CSE of RB_BUILTIN_TYPE
 * in inline function and caller function
 * See also 8998c06461ea0bef11b3aeb30b6d2ab71c8762ba
 */
#if RBIMPL_COMPILER_BEFORE(Clang, 4, 0, 0)
# undef rb_integer_type_p
# define rb_integer_type_p(obj)                                 \
    __extension__ ({                                            \
        const VALUE integer_type_obj = (obj);                   \
        (RB_FIXNUM_P(integer_type_obj) ||                       \
         (!RB_SPECIAL_CONST_P(integer_type_obj) &&              \
          RB_BUILTIN_TYPE(integer_type_obj) == RUBY_T_BIGNUM)); \
    })
#endif
/** @endcond */

RBIMPL_ATTR_PURE()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * @private
 * Defined in ruby/internal/core/rtypeddata.h
 */
static inline bool rbimpl_rtypeddata_p(VALUE obj);

RBIMPL_ATTR_ARTIFICIAL()
/**
 * Identical  to  RB_TYPE_P(),  except  it  raises  exceptions  on  predication
 * failure.
 *
 * @param[in]  v              An object.
 * @param[in]  t              A type.
 * @exception  rb_eTypeError  `obj` is not of type `t`.
 * @exception  rb_eFatal      `obj` is corrupt.
 * @post       Upon successful return `obj` is guaranteed to have type `t`.
 */
static inline void
Check_Type(VALUE v, enum ruby_value_type t)
{
    if (RB_UNLIKELY(! RB_TYPE_P(v, t))) {
        goto unexpected_type;
    }
    else if (t == RUBY_T_DATA && rbimpl_rtypeddata_p(v)) {
        /* Typed data is not simple `T_DATA`, see `rb_check_type` */
        goto unexpected_type;
    }
    else {
        return;
    }

  unexpected_type:
    rb_unexpected_type(v, t);
}

#endif /* RBIMPL_VALUE_TYPE_H */
