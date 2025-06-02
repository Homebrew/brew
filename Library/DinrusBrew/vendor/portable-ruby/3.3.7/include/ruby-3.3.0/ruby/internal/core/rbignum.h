#ifndef RBIMPL_RBIGNUM_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RBIGNUM_H
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
 * @brief      Routines to manipulate struct RBignum.
 * @note       The struct RBignum itself is opaque.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/internal/stdbool.h"

#define RBIGNUM_SIGN rb_big_sign /**< @alias{rb_big_sign} */

/** @cond INTERNAL_MACRO */
#define RBIGNUM_POSITIVE_P RBIGNUM_POSITIVE_P
#define RBIGNUM_NEGATIVE_P RBIGNUM_NEGATIVE_P
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * The "sign" of a bignum.
 *
 * @param[in]  num  An object of RBignum.
 * @retval     1    It is greater than or equal to zero.
 * @retval     0    It is less than zero.
 *
 * @internal
 *
 * Implementation wise, unlike fixnums (which  are 2's complement), bignums are
 * signed  magnitude  system.   Theoretically  it could  be  possible  to  have
 * negative zero  instances.  But  in reality  there is no  way to  create such
 * thing.  Nobody ever needed that kind of insanity.
 */
int rb_big_sign(VALUE num);
RBIMPL_SYMBOL_EXPORT_END()

/**
 * Checks if the bignum is positive.
 * @param[in]  b      An object of RBignum.
 * @retval     false  `b` is less than zero.
 * @retval     true   Otherwise.
 */
static inline bool
RBIGNUM_POSITIVE_P(VALUE b)
{
    RBIMPL_ASSERT_TYPE(b, RUBY_T_BIGNUM);
    return RBIGNUM_SIGN(b);
}

/**
 * Checks if the bignum is negative.
 * @param[in]  b      An object of RBignum.
 * @retval     true   `b` is less than zero.
 * @retval     false  Otherwise.
 */
static inline bool
RBIGNUM_NEGATIVE_P(VALUE b)
{
    RBIMPL_ASSERT_TYPE(b, RUBY_T_BIGNUM);
    return ! RBIGNUM_POSITIVE_P(b);
}

#endif /* RBIMPL_RBIGNUM_H */
