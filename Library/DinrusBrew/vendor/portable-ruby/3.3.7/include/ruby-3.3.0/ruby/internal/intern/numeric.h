#ifndef RBIMPL_INTERN_NUMERIC_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_NUMERIC_H
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
 * @brief      Public APIs related to ::rb_cNumeric.
 */
#include "ruby/internal/attr/cold.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define RB_NUM_COERCE_FUNCS_NEED_OPID 1

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* numeric.c */

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_COLD()
/**
 * Just always raises an exception.
 *
 * @exception  rb_eZeroDivError  Division by zero error.
 */
void rb_num_zerodiv(void);

/**
 * @name Coercion operators.
 *
 * What  is a  coercion?   Well Ruby  is  basically  an OOPL  but  it also  has
 * arithmetic operators.   They are  implemented in  OO manners.   For instance
 * `a+b` is  a binary operation  `+`, whose receiver  is `a`, and  whose (sole)
 * argument is `b`.
 *
 * The problem is, you  often want `a+b == b+a` to hold.  That  is easy if both
 * `a` and `b` belongs to the same class...  Ensuring  `1 + 2 == 2 + 1` is kind
 * of intuitive.  But  if you want `1.0 +  2 == 2 + 1.0`,  things start getting
 * complicated.  `1.0+2` is `Float#+`, while  `2+1.0` is `Integer#+`.  In order
 * to achieve the equality Float's and  Integer's methods must agree with their
 * behaviours.
 *
 * Now.  Floats  versus Integers situation  is still controllable  because they
 * are both  built-in.  But in  Ruby you can  define your own  numeric classes.
 * BigDecimal, which is a rubygems  gem distributed along with the interpreter,
 * is one  of such  examples.  Rational  was another  such example  before.  In
 * short you cannot create list of all possible combination of the classes that
 * could  be  the  operand  of  `+`  operator.  Then  how  do  we  achieve  the
 * commutativity?
 *
 * Here  comes  the concept  of  coercion.   If  a  definition of  an  operator
 * encounters an object  which is unknown to the author,  just assumes that the
 * unknown object  knows how  to handle  the situation.   So for  instance when
 * `1+x` has unknown `x`, it lets the `x` handle this.
 *
 * ```ruby
 * class Foo
 *   def +(x)
 *     if we_know_what_is_x? then
 *       ... # handle here
 *     else
 *       y, z = x.coerce self
 *       return y + z
 *     end
 *   end
 * end
 * ```
 *
 * The `x.coerce` method returns a  2-element array which are "casted" versions
 * of `x` and `self`.
 *
 * @{
 */

/**
 * Coerced binary operation.  This function first coerces the two objects, then
 * applies the operation.
 *
 * @param[in]  lhs            LHS operand.
 * @param[in]  rhs            RHS operand.
 * @param[in]  op             Operator method name.
 * @exception  rb_eTypeError  Coercion failed for some reason.
 * @return     `lhs op rhs`, in a coerced way.
 */
VALUE rb_num_coerce_bin(VALUE lhs, VALUE rhs, ID op);

/**
 * Identical to  rb_num_coerce_bin(), except for return  values.  This function
 * best suits for comparison operators e.g. `<=>`.
 *
 * @param[in]  lhs        LHS operand.
 * @param[in]  rhs        RHS operand.
 * @param[in]  op         Operator method name.
 * @retval     RUBY_Qnil  Coercion failed for some reason.
 * @retval     otherwise  `lhs op rhs`, in a coerced way.
 */
VALUE rb_num_coerce_cmp(VALUE lhs, VALUE rhs, ID op);

/**
 * Identical to  rb_num_coerce_cmp(), except for return  values.  This function
 * best suits for relationship operators e.g. `<=`.
 *
 * @param[in]  lhs           LHS operand.
 * @param[in]  rhs           RHS operand.
 * @param[in]  op            Operator method name.
 * @exception  rb_eArgError  Coercion failed for some reason.
 * @return     `lhs op rhs`, in a coerced way.
 */
VALUE rb_num_coerce_relop(VALUE lhs, VALUE rhs, ID op);

/**
 * This one  is optimised for bitwise  operations, but the API  is identical to
 * rb_num_coerce_bin().
 *
 * @param[in]  lhs           LHS operand.
 * @param[in]  rhs           RHS operand.
 * @param[in]  op            Operator method name.
 * @exception  rb_eArgError  Coercion failed for some reason.
 * @return     `lhs op rhs`, in a coerced way.
 */
VALUE rb_num_coerce_bit(VALUE lhs, VALUE rhs, ID op);

/** @} */

/**
 * Converts  a  numeric  value  into  a  Fixnum.   This  is  not  a  preserving
 * conversion; for instance 1.5 would be converted into 1.
 *
 * @param[in]  val             A numeric object.
 * @exception  rb_eTypeError   No conversion from `val` to Integer.
 * @exception  rb_eRangeError  `val` out of range.
 * @return     A fixnum converted from `val`.
 *
 * @internal
 *
 * This seems used from nowhere?
 */
VALUE rb_num2fix(VALUE val);

/**
 * Generates  a place-value  representation  of the  given  Fixnum, with  given
 * radix.
 *
 * @param[in]  val           A fixnum to stringify.
 * @param[in]  base          `2` to `36` inclusive for each radix.
 * @exception  rb_eArgError  `base` is out of range.
 * @return     An instance of ::rb_cString representing `val`.
 * @pre        `val` must be a Fixnum (no checks performed).
 */
VALUE rb_fix2str(VALUE val, int base);

RBIMPL_ATTR_CONST()
/**
 * Compares two `double`s.  Handy when implementing a spaceship operator.
 *
 * @param[in]  lhs             A value.
 * @param[in]  rhs             Another value.
 * @retval     RB_INT2FIX(-1)  `lhs` is "bigger than" `rhs`.
 * @retval     RB_INT2FIX(1)   `rhs` is "bigger than" `lhs`.
 * @retval     RB_INT2FIX(0)   They are equal.
 * @retval     RUBY_Qnil       Not comparable, e.g. NaN.
 */
VALUE rb_dbl_cmp(double lhs, double rhs);

/**
 * Raises the passed `x` to the power of `y`.
 *
 * @note       The return value can be really big.
 * @note       Also the  return value  can be  really small, in  case `x`  is a
 *             negative number.
 * @param[in]  x          A number.
 * @param[in]  y          Another number.
 * @retval     Inf        Cannot express the result.
 * @retval     1          Either `y` is 0 or `x` is 1.
 * @retval     otherwise  An instance of ::rb_cInteger whose value is `x ** y`.
 *
 * @internal
 *
 * This function  returns Infinity  when `y` is  big enough not  to fit  into a
 * Fixnum.  Warning is issued then.
 */
RUBY_EXTERN VALUE rb_int_positive_pow(long x, unsigned long y);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_NUMERIC_H */
