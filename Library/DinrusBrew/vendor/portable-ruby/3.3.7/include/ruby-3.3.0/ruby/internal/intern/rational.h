#ifndef RBIMPL_INTERN_RATIONAL_H                     /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_RATIONAL_H
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
 * @brief      Public APIs related to ::rb_cRational.
 */
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/arithmetic/long.h" /* INT2FIX is here. */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* rational.c */

/**
 * Identical to rb_rational_new(), except it skips argument validations.  It is
 * thus  dangerous  for extension  libraries.   For  instance `1/0r`  could  be
 * constructed using this.
 *
 * @param[in]  num            Numerator, an instance of ::rb_cInteger.
 * @param[in]  den            Denominator, an instance of ::rb_cInteger.
 * @exception  rb_eTypeError  Either argument is not an Integer.
 * @return     An instance of ::rb_cRational whose value is `(num/den)r`.
 */
VALUE rb_rational_raw(VALUE num, VALUE den);

/**
 * Shorthand  of  `(x/1)r`.  As  `x`  is  already  an Integer,  it  practically
 * converts it into a Rational of the identical value.
 *
 * @param[in]  x  An instance of ::rb_cInteger.
 * @return     An instance of ::rb_cRational, whose value is `(x/1)r`.
 */
#define rb_rational_raw1(x) rb_rational_raw((x), INT2FIX(1))

/** @alias{rb_rational_raw} */
#define rb_rational_raw2(x,y) rb_rational_raw((x), (y))

/**
 * Constructs a Rational,  with reduction.  This returns  for instance `(2/3)r`
 * for `rb_rational_new(INT2NUM(-384), INT2NUM(-576))`.
 *
 * @param[in]  num               Numerator, an instance of ::rb_cInteger.
 * @param[in]  den               Denominator, an instance of ::rb_cInteger.
 * @exception  rb_eZeroDivError  `den` is zero.
 * @return     An instance of ::rb_cRational whose value is `(num/den)r`.
 */
VALUE rb_rational_new(VALUE num, VALUE den);

/**
 * Shorthand  of  `(x/1)r`.  As  `x`  is  already  an Integer,  it  practically
 * converts it into a Rational of the identical value.
 *
 * @param[in]  x  An instance of ::rb_cInteger.
 * @return     An instance of ::rb_cRational, whose value is `(x/1)r`.
 */
#define rb_rational_new1(x) rb_rational_new((x), INT2FIX(1))

/** @alias{rb_rational_new} */
#define rb_rational_new2(x,y) rb_rational_new((x), (y))

/**
 * Converts various values into a Rational.  This function accepts:
 *
 * - Instances of ::rb_cInteger (taken as-is),
 * - Instances of ::rb_cRational (taken as-is),
 * - Instances of ::rb_cFloat (applies `#to_r`),
 * - Instances of ::rb_cComplex (applies `#to_r`),
 * - Instances of ::rb_cString (applies `#to_r`),
 * - Other objects that respond to `#to_r`.
 *
 * It (possibly  recursively) applies  `#to_r` until  both sides  become either
 * Integer or Rational, then divides them.
 *
 * As a  special case, passing  ::RUBY_Qundef to `den`  is the same  as passing
 * `RB_INT2NUM(1)`.
 *
 * @param[in]  num                   Numerator (see above).
 * @param[in]  den                   Denominator (see above).
 * @exception  rb_eTypeError         Passed something not described above.
 * @exception  rb_eFloatDomainError  `#to_r` produced Nan/Inf.
 * @exception  rb_eZeroDivError      `#to_r` produced zero for `den`.
 * @return     An instance of ::rb_cRational whose value is `(num/den)r`.
 *
 * @internal
 *
 * This was the implementation of `Kernel#Rational` before, but they diverged.
 */
VALUE rb_Rational(VALUE num, VALUE den);

/**
 * Shorthand of  `(x/1)r`.  It practically converts  it into a Rational  of the
 * identical value.
 *
 * @param[in]  x  ::rb_cInteger, ::rb_cRational, or  something that responds to
 *                `#to_r`.
 * @return     An instance of ::rb_cRational, whose value is `(x/1)r`.
 */
#define rb_Rational1(x) rb_Rational((x), INT2FIX(1))

/** @alias{rb_Rational} */
#define rb_Rational2(x,y) rb_Rational((x), (y))

RBIMPL_ATTR_PURE()
/**
 * Queries the numerator of the passed Rational.
 *
 * @param[in]  rat  An instance of ::rb_cRational.
 * @return     Its numerator part, which is an instance of ::rb_cInteger.
 */
VALUE rb_rational_num(VALUE rat);

RBIMPL_ATTR_PURE()
/**
 * Queries the denominator of the passed Rational.
 *
 * @param[in]  rat  An instance of ::rb_cRational.
 * @return     Its  denominator part,  which  is an  instance of  ::rb_cInteger
 *             greater than or equal to one..
 */
VALUE rb_rational_den(VALUE rat);

/**
 * Simplified  approximation of  a float.   It returns  a rational  `rat` which
 * satisfies:
 *
 * ```
 * flt - |prec| <= rat <= flt + |prec|
 * ```
 *
 * ```ruby
 * 3.141592.rationalize(0.001) # => (201/64)r
 * 3.141592.rationalize(0.01)' # => (22/7)r
 * 3.141592.rationalize(0.1)'  # => (16/5)r
 * 3.141592.rationalize(1)'    # => (3/1)r
 * ```
 *
 * @param[in]  flt   An instance of ::rb_cFloat to rationalise.
 * @param[in]  prec  Another ::rb_cFloat, which is the "precision".
 * @return     Approximation of `flt`, in ::rb_cRational.
 */
VALUE rb_flt_rationalize_with_prec(VALUE flt, VALUE prec);

/**
 * Identical   to   rb_flt_rationalize_with_prec(),  except   it   auto-detects
 * appropriate precision depending on the passed value.
 *
 * @param[in]  flt   An instance of ::rb_cFloat to rationalise.
 * @return     Approximation of `flt`, in ::rb_cRational.
 */
VALUE rb_flt_rationalize(VALUE flt);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_RATIONAL_H */
