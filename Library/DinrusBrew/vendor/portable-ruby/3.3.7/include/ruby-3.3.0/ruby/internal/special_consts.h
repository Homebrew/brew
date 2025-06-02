#ifndef RBIMPL_SPECIAL_CONSTS_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_SPECIAL_CONSTS_H
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
 * @brief      Defines enum ::ruby_special_consts.
 * @see        Sasada,  K.,  "A  Lightweight Representation  of  Floating-Point
 *             Numbers  on  Ruby Interpreter",  in  proceedings  of 10th  JSSST
 *             SIGPPL  Workshop   on  Programming  and   Programming  Languages
 *             (PPL2008), pp. 9-16, 2008.
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/attr/enum_extensibility.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"

/**
 * @private
 * @warning  Do not touch this macro.
 * @warning  It is an implementation detail.
 * @warning  The  value of  this  macro  must match  for  ruby  itself and  all
 *           extension  libraries, otherwise  serious  memory corruption  shall
 *           occur.
 */
#if defined(USE_FLONUM)
# /* Take that. */
#elif SIZEOF_VALUE >= SIZEOF_DOUBLE
# define USE_FLONUM 1
#else
# define USE_FLONUM 0
#endif

/** This is an old name of #RB_TEST.  Not sure which name is preferred. */
#define RTEST           RB_TEST

#define FIXNUM_P        RB_FIXNUM_P            /**< @old{RB_FIXNUM_P} */
#define IMMEDIATE_P     RB_IMMEDIATE_P         /**< @old{RB_IMMEDIATE_P} */
#define NIL_P           RB_NIL_P               /**< @old{RB_NIL_P} */
#define SPECIAL_CONST_P RB_SPECIAL_CONST_P     /**< @old{RB_SPECIAL_CONST_P} */
#define STATIC_SYM_P    RB_STATIC_SYM_P        /**< @old{RB_STATIC_SYM_P} */

#define Qfalse          RUBY_Qfalse            /**< @old{RUBY_Qfalse} */
#define Qnil            RUBY_Qnil              /**< @old{RUBY_Qnil} */
#define Qtrue           RUBY_Qtrue             /**< @old{RUBY_Qtrue} */
#define Qundef          RUBY_Qundef            /**< @old{RUBY_Qundef} */

#define FIXNUM_FLAG        RUBY_FIXNUM_FLAG    /**< @old{RUBY_FIXNUM_FLAG} */
#define FLONUM_FLAG        RUBY_FLONUM_FLAG    /**< @old{RUBY_FLONUM_FLAG} */
#define FLONUM_MASK        RUBY_FLONUM_MASK    /**< @old{RUBY_FLONUM_MASK} */
#define FLONUM_P           RB_FLONUM_P         /**< @old{RB_FLONUM_P} */
#define IMMEDIATE_MASK     RUBY_IMMEDIATE_MASK /**< @old{RUBY_IMMEDIATE_MASK} */
#define SYMBOL_FLAG        RUBY_SYMBOL_FLAG    /**< @old{RUBY_SYMBOL_FLAG} */

/** @cond INTERNAL_MACRO */
#define RB_FIXNUM_P        RB_FIXNUM_P
#define RB_FLONUM_P        RB_FLONUM_P
#define RB_IMMEDIATE_P     RB_IMMEDIATE_P
#define RB_NIL_P           RB_NIL_P
#define RB_SPECIAL_CONST_P RB_SPECIAL_CONST_P
#define RB_STATIC_SYM_P    RB_STATIC_SYM_P
#define RB_TEST            RB_TEST
#define RB_UNDEF_P         RB_UNDEF_P
#define RB_NIL_OR_UNDEF_P  RB_NIL_OR_UNDEF_P
/** @endcond */

/** special constants - i.e. non-zero and non-fixnum constants */
enum
RBIMPL_ATTR_ENUM_EXTENSIBILITY(closed)
ruby_special_consts {
#if defined(__DOXYGEN__)
    RUBY_Qfalse,                /**< @see ::rb_cFalseClass */
    RUBY_Qtrue,                 /**< @see ::rb_cTrueClass */
    RUBY_Qnil,                  /**< @see ::rb_cNilClass */
    RUBY_Qundef,                /**< Represents so-called undef. */
    RUBY_IMMEDIATE_MASK,        /**< Bit mask detecting special consts. */
    RUBY_FIXNUM_FLAG,           /**< Flag to denote a fixnum. */
    RUBY_FLONUM_MASK,           /**< Bit mask detecting a flonum. */
    RUBY_FLONUM_FLAG,           /**< Flag to denote a flonum. */
    RUBY_SYMBOL_FLAG,           /**< Flag to denote a static symbol. */
#elif USE_FLONUM
    RUBY_Qfalse         = 0x00, /* ...0000 0000 */
    RUBY_Qnil           = 0x04, /* ...0000 0100 */
    RUBY_Qtrue          = 0x14, /* ...0001 0100 */
    RUBY_Qundef         = 0x24, /* ...0010 0100 */
    RUBY_IMMEDIATE_MASK = 0x07, /* ...0000 0111 */
    RUBY_FIXNUM_FLAG    = 0x01, /* ...xxxx xxx1 */
    RUBY_FLONUM_MASK    = 0x03, /* ...0000 0011 */
    RUBY_FLONUM_FLAG    = 0x02, /* ...xxxx xx10 */
    RUBY_SYMBOL_FLAG    = 0x0c, /* ...xxxx 1100 */
#else
    RUBY_Qfalse         = 0x00, /* ...0000 0000 */
    RUBY_Qnil           = 0x02, /* ...0000 0010 */
    RUBY_Qtrue          = 0x06, /* ...0000 0110 */
    RUBY_Qundef         = 0x0a, /* ...0000 1010 */
    RUBY_IMMEDIATE_MASK = 0x03, /* ...0000 0011 */
    RUBY_FIXNUM_FLAG    = 0x01, /* ...xxxx xxx1 */
    RUBY_FLONUM_MASK    = 0x00, /* any values ANDed with FLONUM_MASK cannot be FLONUM_FLAG */
    RUBY_FLONUM_FLAG    = 0x02, /* ...0000 0010 */
    RUBY_SYMBOL_FLAG    = 0x0e, /* ...xxxx 1110 */
#endif

    RUBY_SPECIAL_SHIFT  = 8 /**< Least significant 8 bits are reserved. */
};

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Emulates Ruby's "if" statement.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     false  `obj` is either ::RUBY_Qfalse or ::RUBY_Qnil.
 * @retval     true   Anything else.
 *
 * @internal
 *
 * It HAS to be `__attribute__((const))` in  order for clang to properly deduce
 * `__builtin_assume()`.
 */
static inline bool
RB_TEST(VALUE obj)
{
    /*
     * if USE_FLONUM
     *  Qfalse:  ....0000 0000
     *  Qnil:    ....0000 0100
     * ~Qnil:    ....1111 1011
     *  v        ....xxxx xxxx
     * ----------------------------
     *  RTEST(v) ....xxxx x0xx
     *
     * if ! USE_FLONUM
     *  Qfalse:  ....0000 0000
     *  Qnil:    ....0000 0010
     * ~Qnil:    ....1111 1101
     *  v        ....xxxx xxxx
     * ----------------------------
     *  RTEST(v) ....xxxx xx0x
     *
     *  RTEST(v) can be 0 if and only if (v == Qfalse || v == Qnil).
     */
    return obj & ~RUBY_Qnil;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if the given object is nil.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     true   `obj` is ::RUBY_Qnil.
 * @retval     false  Anything else.
 */
static inline bool
RB_NIL_P(VALUE obj)
{
    return obj == RUBY_Qnil;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if the given object is undef.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     true   `obj` is ::RUBY_Qundef.
 * @retval     false  Anything else.
 */
static inline bool
RB_UNDEF_P(VALUE obj)
{
    return obj == RUBY_Qundef;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX14)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if the given object is nil or undef.  Can be used to see if
 * a keyword argument is not given or given `nil`.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     true   `obj` is ::RUBY_Qnil or ::RUBY_Qundef.
 * @retval     false  Anything else.
 */
static inline bool
RB_NIL_OR_UNDEF_P(VALUE obj)
{
    /*
     * if USE_FLONUM
     *  Qundef:       ....0010 0100
     *  Qnil:         ....0000 0100
     *  mask:         ....1101 1111
     *  common_bits:  ....0000 0100
     * ---------------------------------
     *  Qnil & mask   ....0000 0100
     *  Qundef & mask ....0000 0100
     *
     * if ! USE_FLONUM
     *  Qundef:       ....0000 1010
     *  Qnil:         ....0000 0010
     *  mask:         ....1111 0111
     *  common_bits:  ....0000 0010
     * ----------------------------
     *  Qnil & mask   ....0000 0010
     *  Qundef & mask ....0000 0010
     *
     *  NIL_OR_UNDEF_P(v) can be true only when v is Qundef or Qnil.
     */
    const VALUE mask = ~(RUBY_Qundef ^ RUBY_Qnil);
    const VALUE common_bits = RUBY_Qundef & RUBY_Qnil;
    return (obj & mask) == common_bits;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if the given object is a so-called Fixnum.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     true   `obj` is a Fixnum.
 * @retval     false  Anything else.
 * @note       Fixnum was  a thing  in the  20th century, but  it is  rather an
 *             implementation detail today.
 */
static inline bool
RB_FIXNUM_P(VALUE obj)
{
    return obj & RUBY_FIXNUM_FLAG;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX14)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if the given object is a static symbol.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     true   `obj` is a static symbol
 * @retval     false  Anything else.
 * @see        RB_DYNAMIC_SYM_P()
 * @see        RB_SYMBOL_P()
 * @note       These days  there are static  and dynamic symbols, just  like we
 *             once had Fixnum/Bignum back in the old days.
 */
static inline bool
RB_STATIC_SYM_P(VALUE obj)
{
    RBIMPL_ATTR_CONSTEXPR(CXX14)
    const VALUE mask = ~(RBIMPL_VALUE_FULL << RUBY_SPECIAL_SHIFT);
    return (obj & mask) == RUBY_SYMBOL_FLAG;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if the given object is a so-called Flonum.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     true   `obj` is a Flonum.
 * @retval     false  Anything else.
 * @see        RB_FLOAT_TYPE_P()
 * @note       These days there are Flonums and non-Flonum floats, just like we
 *             once had Fixnum/Bignum back in the old days.
 */
static inline bool
RB_FLONUM_P(VALUE obj)
{
#if USE_FLONUM
    return (obj & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG;
#else
    return false;
#endif
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if  the given  object is  an immediate  i.e. an  object which  has no
 * corresponding storage inside of the object space.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     true   `obj` is a Flonum.
 * @retval     false  Anything else.
 * @see        RB_FLOAT_TYPE_P()
 * @note       The concept of "immediate" is purely C specific.
 */
static inline bool
RB_IMMEDIATE_P(VALUE obj)
{
    return obj & RUBY_IMMEDIATE_MASK;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if the given object is of enum ::ruby_special_consts.
 *
 * @param[in]  obj    An arbitrary ruby object.
 * @retval     true   `obj` is a special constant.
 * @retval     false  Anything else.
 */
static inline bool
RB_SPECIAL_CONST_P(VALUE obj)
{
    return RB_IMMEDIATE_P(obj) || obj == RUBY_Qfalse;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
/**
 * Identical to RB_SPECIAL_CONST_P, except it returns a ::VALUE.
 *
 * @param[in]  obj          An arbitrary ruby object.
 * @retval     RUBY_Qtrue   `obj` is a special constant.
 * @retval     RUBY_Qfalse  Anything else.
 *
 * @internal
 *
 * This  function is  to mimic  old  rb_special_const_p macro  but have  anyone
 * actually used its return value?  Wasn't it just something no one needed?
 */
static inline VALUE
rb_special_const_p(VALUE obj)
{
    return RB_SPECIAL_CONST_P(obj) * RUBY_Qtrue;
}

/**
 * @cond INTERNAL_MACRO
 * See [ruby-dev:27513] for the following macros.
 */
#define RUBY_Qfalse RBIMPL_CAST((VALUE)RUBY_Qfalse)
#define RUBY_Qtrue  RBIMPL_CAST((VALUE)RUBY_Qtrue)
#define RUBY_Qnil   RBIMPL_CAST((VALUE)RUBY_Qnil)
#define RUBY_Qundef RBIMPL_CAST((VALUE)RUBY_Qundef)
/** @endcond */

#endif /* RBIMPL_SPECIAL_CONSTS_H */
