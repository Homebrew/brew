#ifndef RBIMPL_INTERN_RANGE_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_RANGE_H
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
 * @brief      Public APIs related to ::rb_cRange.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* range.c */

/**
 * Creates a new Range.
 *
 * @param[in]  beg           "Left" or "lowest" endpoint of the range.
 * @param[in]  end           "Right" or "highest" endpoint of the range.
 * @param[in]  excl          Whether the range is open-ended.
 * @exception  rb_eArgError  `beg` and `end` are not comparable.
 * @note       These days both  endpoints can be ::RUBY_Qnil,  which means that
 *             endpoint is unbound.
 */
VALUE rb_range_new(VALUE beg, VALUE end, int excl);

RBIMPL_ATTR_NONNULL(())
/**
 * Deconstructs  a numerical  range.  As  the  arguments are  `long` based,  it
 * expects everything are in the `long` domain.
 *
 * @param[in]   range           A range of numerical endpoints.
 * @param[out]  begp            Return value buffer.
 * @param[out]  lenp            Return value buffer.
 * @param[in]   len             Updated length.
 * @param[in]   err             In case `len` is out of range...
 *                                - `0`: returns ::RUBY_Qnil.
 *                                - `1`: raises  ::rb_eRangeError.
 *                                - `2`: `beg` and `len` expanded accordingly.
 * @exception   rb_eTypeError   `range` is not a numerical range.
 * @exception   rb_eRangeError  `range` cannot fit into `long`.
 * @retval      RUBY_Qfalse     `range` is not an ::rb_cRange.
 * @retval      RUBY_Qnil       `len` is out of `range` but `err` is zero.
 * @retval      RUBY_Qtrue      Otherwise.
 * @post        `beg` is the (possibly updated) left endpoint.
 * @post        `len` is the (possibly updated) length of the range.
 *
 * @internal
 *
 * The complex  error handling  switch reflects the  fact that  `Array#[]=` and
 * `String#[]=` behave differently when they take ranges.
 */
VALUE rb_range_beg_len(VALUE range, long *begp, long *lenp, long len, int err);

RBIMPL_ATTR_NONNULL(())
/**
 * Deconstructs a range into its components.
 *
 * @param[in]   range        Range or range-ish object.
 * @param[out]  begp         Return value buffer.
 * @param[out]  endp         Return value buffer.
 * @param[out]  exclp        Return value buffer.
 * @retval      RUBY_Qfalse  `range` is not an instance of ::rb_cRange.
 * @retval      RUBY_Qtrue   Argument pointers are updated.
 * @post        `*begp` is the left endpoint of the range.
 * @post        `*endp` is the right endpoint of the range.
 * @post        `*exclp` is whether the range is open-ended or not.
 */
int rb_range_values(VALUE range, VALUE *begp, VALUE *endp, int *exclp);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_RANGE_H */
