#ifndef  RBIMPL_INTERN_COMPAR_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define  RBIMPL_INTERN_COMPAR_H
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
 * @brief      Public APIs related to ::rb_mComparable.
 */
#include "ruby/internal/attr/cold.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* bignum.c */

/**
 * Canonicalises the passed `val`, which is the return value of `a <=> b`, into
 * C's `{-1, 0, 1}`.  This can be  handy when you implement a callback function
 * to pass to `qsort(3)` etc.
 *
 * @param[in]  val           Return value of a space ship operator.
 * @param[in]  a             Comparison LHS.
 * @param[in]  b             Comparison RHS.
 * @exception  rb_eArgError  `a` and `b` are not comparable each other.
 * @retval     -1            `val` is less than zero.
 * @retval     0             `val` is equal to zero.
 * @retval     1             `val` is greater than zero.
 */
int rb_cmpint(VALUE val, VALUE a, VALUE b);

/* compar.c */

RBIMPL_ATTR_COLD()
RBIMPL_ATTR_NORETURN()
/**
 * Raises "comparison failed" error.
 *
 * @param[in]  a             Comparison LHS.
 * @param[in]  b             Comparison RHS.
 * @exception  rb_eArgError  `a` and `b` are not comparable each other.
 */
void rb_cmperr(VALUE a, VALUE b);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_COMPAR_H */
