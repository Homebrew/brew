#ifndef RBIMPL_ARITHMETIC_LONG_LONG_H                /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_LONG_LONG_H
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
 * @brief      Arithmetic conversion between C's `long long` and Ruby's.
 */
#include "ruby/internal/value.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/special_consts.h"
#include "ruby/backward/2/long_long.h"

#define RB_LL2NUM  rb_ll2num_inline   /**< @alias{rb_ll2num_inline} */
#define RB_ULL2NUM rb_ull2num_inline  /**< @alias{rb_ull2num_inline} */
#define LL2NUM     RB_LL2NUM          /**< @old{RB_LL2NUM} */
#define ULL2NUM    RB_ULL2NUM         /**< @old{RB_ULL2NUM} */
#define RB_NUM2LL  rb_num2ll_inline   /**< @alias{rb_num2ll_inline} */
#define RB_NUM2ULL rb_num2ull_inline  /**< @alias{rb_num2ull_inline} */
#define NUM2LL     RB_NUM2LL          /**< @old{RB_NUM2LL} */
#define NUM2ULL    RB_NUM2ULL         /**< @old{RB_NUM2ULL} */

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * Converts a C's `long long` into an instance of ::rb_cInteger.
 *
 * @param[in]  num  Arbitrary `long long` value.
 * @return     An instance of ::rb_cInteger.
 */
VALUE rb_ll2inum(LONG_LONG num);

/**
 * Converts a C's `unsigned long long` into an instance of ::rb_cInteger.
 *
 * @param[in]  num  Arbitrary `unsigned long long` value.
 * @return     An instance of ::rb_cInteger.
 */
VALUE rb_ull2inum(unsigned LONG_LONG num);

/**
 * Converts an instance of ::rb_cNumeric into C's `long long`.
 *
 * @param[in]  num             Something numeric.
 * @exception  rb_eTypeError   `num` is not a numeric.
 * @exception  rb_eRangeError  `num` is out of range of `long long`.
 * @return     The passed value converted into C's `long long`.
 */
LONG_LONG rb_num2ll(VALUE num);

/**
 * Converts an instance of ::rb_cNumeric into C's `unsigned long long`.
 *
 * @param[in]  num             Something numeric.
 * @exception  rb_eTypeError   `num` is not a numeric.
 * @exception  rb_eRangeError  `num` is out of range of `unsigned long long`.
 * @return     The passed value converted into C's `unsigned long long`.
 */
unsigned LONG_LONG rb_num2ull(VALUE num);
RBIMPL_SYMBOL_EXPORT_END()

/**
 * Converts a C's `long long` into an instance of ::rb_cInteger.
 *
 * @param[in]  n  Arbitrary `long long` value.
 * @return     An instance of ::rb_cInteger
 */
static inline VALUE
rb_ll2num_inline(LONG_LONG n)
{
    if (FIXABLE(n)) return LONG2FIX((long)n);
    return rb_ll2inum(n);
}

/**
 * Converts a C's `unsigned long long` into an instance of ::rb_cInteger.
 *
 * @param[in]  n  Arbitrary `unsigned long long` value.
 * @return     An instance of ::rb_cInteger
 */
static inline VALUE
rb_ull2num_inline(unsigned LONG_LONG n)
{
    if (POSFIXABLE(n)) return LONG2FIX((long)n);
    return rb_ull2inum(n);
}

/**
 * Converts an instance of ::rb_cNumeric into C's `long long`.
 *
 * @param[in]  x               Something numeric.
 * @exception  rb_eTypeError   `x` is not a numeric.
 * @exception  rb_eRangeError  `x` is out of range of `long long`.
 * @return     The passed value converted into C's `long long`.
 */
static inline LONG_LONG
rb_num2ll_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return RB_FIX2LONG(x);
    else
        return rb_num2ll(x);
}

/**
 * Converts an instance of ::rb_cNumeric into C's `unsigned long long`.
 *
 * @param[in]  x               Something numeric.
 * @exception  rb_eTypeError   `x` is not a numeric.
 * @exception  rb_eRangeError  `x` is out of range of `unsigned long long`.
 * @return     The passed value converted into C's `unsigned long long`.
 */
static inline unsigned LONG_LONG
rb_num2ull_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return RB_FIX2LONG(x);
    else
        return rb_num2ull(x);
}

#endif /* RBIMPL_ARITHMETIC_LONG_LONG_H */
