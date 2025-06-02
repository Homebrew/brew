#ifndef RBIMPL_ARITHMETIC_CHAR_H                     /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_CHAR_H
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
 * @brief      Arithmetic conversion between C's `char` and Ruby's.
 */
#include "ruby/internal/arithmetic/int.h"  /* NUM2INT is here, but */
#include "ruby/internal/arithmetic/long.h" /* INT2FIX is here.*/
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rstring.h"
#include "ruby/internal/value_type.h"

#define RB_NUM2CHR rb_num2char_inline /**< @alias{rb_num2char_inline} */
#define NUM2CHR    RB_NUM2CHR         /**< @old{RB_NUM2CHR} */
#define CHR2FIX    RB_CHR2FIX         /**< @old{RB_CHR2FIX} */

/** @cond INTERNAL_MACRO */
#define RB_CHR2FIX RB_CHR2FIX
/** @endcond */

RBIMPL_ATTR_CONST_UNLESS_DEBUG()
RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(CXX14)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Converts a C's `unsigned char` into an instance of ::rb_cInteger.
 *
 * @param[in]  c  Arbitrary `unsigned char` value.
 * @return     An instance of ::rb_cInteger.
 *
 * @internal
 *
 * Nobody explicitly states this but in  Ruby, a char means an unsigned integer
 * value of  range 0..255.   This is  a general principle.   AFAIK there  is no
 * single line of code where char is signed.
 */
static inline VALUE
RB_CHR2FIX(unsigned char c)
{
    return RB_INT2FIX(c);
}

/**
 * Converts an instance of ::rb_cNumeric into  C's `char`.  At the same time it
 * accepts a String of more than one character, and returns its first byte.  In
 * the  early days  there  was a  Ruby level  "character"  literal `?c`,  which
 * roughly worked this way.
 *
 * @param[in]  x               Either a string or a numeric.
 * @exception  rb_eTypeError   `x` is not a numeric.
 * @exception  rb_eRangeError  `x` is out of range of `unsigned int`.
 * @return     The passed value converted into C's `char`.
 */
static inline char
rb_num2char_inline(VALUE x)
{
    if (RB_TYPE_P(x, RUBY_T_STRING) && (RSTRING_LEN(x)>=1))
        return RSTRING_PTR(x)[0];
    else
        return RBIMPL_CAST((char)RB_NUM2INT(x));
}

#endif /* RBIMPL_ARITHMETIC_CHAR_H */
