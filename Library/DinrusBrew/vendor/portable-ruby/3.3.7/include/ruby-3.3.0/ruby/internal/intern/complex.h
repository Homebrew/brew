#ifndef RBIMPL_INTERN_COMPLEX_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_COMPLEX_H
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
 * @brief      Public APIs related to ::rb_cComplex.
 */
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/arithmetic/long.h" /* INT2FIX is here. */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* complex.c */

/**
 * Identical  to rb_complex_new(),  except it  assumes both  arguments are  not
 * instances of ::rb_cComplex.  It is thus dangerous for extension libraries.
 *
 * @param[in]  real  Real part, in any numeric except Complex.
 * @param[in]  imag  Imaginary part, in any numeric except Complex.
 * @return     An instance of ::rb_cComplex whose value is `real + (imag)i`.
 */
VALUE rb_complex_raw(VALUE real, VALUE imag);

/**
 * Shorthand of  `x+0i`.  It  practically converts  `x` into  a Complex  of the
 * identical value.
 *
 * @param[in]  x  Any numeric except Complex.
 * @return     An instance of ::rb_cComplex, whose value is `x + 0i`.
 */
#define rb_complex_raw1(x) rb_complex_raw((x), INT2FIX(0))

/** @alias{rb_complex_raw} */
#define rb_complex_raw2(x,y) rb_complex_raw((x), (y))

/**
 * Constructs a Complex, by first multiplying the imaginary part with `1i` then
 * adds it  to the real part.   This definition doesn't need  both arguments be
 * real numbers.  It  can happily combine two instances  of ::rb_cComplex (with
 * rotating the latter one).
 *
 * @param[in]  real  An instance of ::rb_cNumeric.
 * @param[in]  imag  Another instance of ::rb_cNumeric.
 * @return     An instance of ::rb_cComplex whose value is `imag * 1i + real`.
 */
VALUE rb_complex_new(VALUE real, VALUE imag);

/**
 * Shorthand of  `x+0i`.  It  practically converts  `x` into  a Complex  of the
 * identical value.
 *
 * @param[in]  x  Any numeric value.
 * @return     An instance of ::rb_cComplex, whose value is `x + 0i`.
 */
#define rb_complex_new1(x) rb_complex_new((x), INT2FIX(0))

/** @alias{rb_complex_new} */
#define rb_complex_new2(x,y) rb_complex_new((x), (y))

/**
 * Constructs a  Complex using polar representations.   Unlike rb_complex_new()
 * it makes no sense to pass non-real instances to this function.
 *
 * @param[in]  abs  Magnitude, in any numeric except Complex.
 * @param[in]  arg  Angle, in radians, in any numeric except Complex.
 * @return     An  instance  of ::rb_cComplex  which  denotes  the given  polar
 *             coordinates.
 */
VALUE rb_complex_new_polar(VALUE abs, VALUE arg);

RBIMPL_ATTR_DEPRECATED(("by: rb_complex_new_polar"))
/** @old{rb_complex_new_polar} */
VALUE rb_complex_polar(VALUE abs, VALUE arg);

RBIMPL_ATTR_PURE()
/**
 * Queries the real part of the passed Complex.
 *
 * @param[in]  z  An instance of ::rb_cComplex.
 * @return     Its real part, which is an instance of ::rb_cNumeric.
 */
VALUE rb_complex_real(VALUE z);

RBIMPL_ATTR_PURE()
/**
 * Queries the imaginary part of the passed Complex.
 *
 * @param[in]  z  An instance of ::rb_cComplex.
 * @return     Its imaginary part, which is an instance of ::rb_cNumeric.
 */
VALUE rb_complex_imag(VALUE z);

/**
 * Performs addition of the passed two objects.
 *
 * @param[in]  x  An instance of ::rb_cComplex.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x + y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_complex_plus(VALUE x, VALUE y);

/**
 * Performs subtraction of the passed two objects.
 *
 * @param[in]  x  An instance of ::rb_cComplex.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x - y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_complex_minus(VALUE x, VALUE y);

/**
 * Performs multiplication of the passed two objects.
 *
 * @param[in]  x  An instance of ::rb_cComplex.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x * y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_complex_mul(VALUE x, VALUE y);

/**
 * Performs division of the passed two objects.
 *
 * @param[in]  x  An instance of ::rb_cComplex.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x / y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_complex_div(VALUE x, VALUE y);

/**
 * Performs negation of the passed object.
 *
 * @param[in]  z  An instance of ::rb_cComplex.
 * @return     What `-z` evaluates to.
 */
VALUE rb_complex_uminus(VALUE z);

/**
 * Performs complex conjugation of the passed object.
 *
 * @param[in]  z  An instance of ::rb_cComplex.
 * @return     Its complex conjugate, in ::rb_cComplex.
 */
VALUE rb_complex_conjugate(VALUE z);

/**
 * Queries the absolute (or the magnitude) of the passed object.
 *
 * @param[in]  z  An instance of ::rb_cComplex.
 * @return     Its magnitude, in ::rb_cFloat.
 */
VALUE rb_complex_abs(VALUE z);

/**
 * Queries the argument (or the angle) of the passed object.
 *
 * @param[in]  z  An instance of ::rb_cComplex.
 * @return     Its magnitude, in ::rb_cFloat.
 */
VALUE rb_complex_arg(VALUE z);

/**
 * Performs exponentiation of the passed two objects.
 *
 * @param[in]  base  An instance of ::rb_cComplex.
 * @param[in]  exp   Arbitrary ruby object.
 * @return     What `base ** exp` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_complex_pow(VALUE base, VALUE exp);

/**
 * Identical to rb_complex_new(),  except it takes the arguments  as C's double
 * instead of Ruby's object.
 *
 * @param[in]  real  Real part.
 * @param[in]  imag  Imaginary part.
 * @return     An instance of ::rb_cComplex whose value is `real + (imag)i`.
 */
VALUE rb_dbl_complex_new(double real, double imag);

/** @alias{rb_complex_plus} */
#define rb_complex_add rb_complex_plus

/** @alias{rb_complex_minus} */
#define rb_complex_sub rb_complex_minus

/** @alias{rb_complex_uminus} */
#define rb_complex_nagate rb_complex_uminus

/**
 * Converts various values into a Complex.  This function accepts:
 *
 * - Instances of ::rb_cComplex (taken as-is),
 * - Instances of ::rb_cNumeric (adds `0i`),
 * - Instances of ::rb_cString  (parses),
 * - Other objects that respond to `#to_c`.
 *
 * It (possibly recursively) applies `#to_c`  until both sides become a Complex
 * value, then computes `imag * 1i + real`.
 *
 * As a  special case, passing ::RUBY_Qundef  to `imag` is the  same as passing
 * `RB_INT2NUM(0)`.
 *
 * @param[in]  real           Real part (see above).
 * @param[in]  imag           Imaginary part (see above).
 * @exception  rb_eTypeError  Passed something not described above.
 * @return     An instance of ::rb_cComplex whose value is `1i * imag + real`.
 *
 * @internal
 *
 * This was the implementation of `Kernel#Complex` before, but they diverged.
 */
VALUE rb_Complex(VALUE real, VALUE imag);

/**
 * Shorthand of  `x+0i`.  It  practically converts  `x` into  a Complex  of the
 * identical value.
 *
 * @param[in]  x  ::rb_cNumeric,  ::rb_cString, or  something that  responds to
 *                `#to_c`.
 * @return     An instance of ::rb_cComplex, whose value is `x + 0i`.
 */
#define rb_Complex1(x) rb_Complex((x), INT2FIX(0))

/** @alias{rb_Complex} */
#define rb_Complex2(x,y) rb_Complex((x), (y))

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_COMPLEX_H */
