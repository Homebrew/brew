#ifndef RBIMPL_ARITHMETIC_DOUBLE_H                   /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_DOUBLE_H
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
 * @brief      Arithmetic conversion between C's `double` and Ruby's.
 */
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

#define NUM2DBL      rb_num2dbl       /**< @old{rb_num2dbl} */
#define RFLOAT_VALUE rb_float_value   /**< @old{rb_float_value} */
#define DBL2NUM      rb_float_new     /**< @old{rb_float_new} */

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * Converts an instance of ::rb_cNumeric into C's `double`.
 *
 * @param[in]  num             Something numeric.
 * @exception  rb_eTypeError   `num` is not a numeric.
 * @return     The passed value converted into C's `double`.
 */
double rb_num2dbl(VALUE num);

RBIMPL_ATTR_PURE()
/**
 * Extracts its double value from an instance of ::rb_cFloat.
 *
 * @param[in]  num  An instance of ::rb_cFloat.
 * @pre        Must not pass anything other than a Fixnum.
 * @return     The passed value converted into C's `double`.
 */
double rb_float_value(VALUE num);

/**
 * Converts a C's `double` into an instance of ::rb_cFloat.
 *
 * @param[in]  d  Arbitrary `double` value.
 * @return     An instance of ::rb_cFloat.
 */
VALUE rb_float_new(double d);

/**
 * Identical to rb_float_new(), except it does not generate Flonums.
 *
 * @param[in]  d  Arbitrary `double` value.
 * @return     An instance of ::rb_cFloat.
 *
 * @internal
 *
 * @shyouhei has no idea why it is here.
 */
VALUE rb_float_new_in_heap(double d);
RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_ARITHMETIC_DOUBLE_H */
