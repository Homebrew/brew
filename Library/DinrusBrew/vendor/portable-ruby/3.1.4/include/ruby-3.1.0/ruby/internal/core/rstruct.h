#ifndef RBIMPL_RSTRUCT_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RSTRUCT_H
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
 * @brief      Routines to manipulate struct RStruct.
 * @note       The struct RStruct itself is opaque.
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/arithmetic/int.h"
#if !defined RUBY_EXPORT && !defined RUBY_NO_OLD_COMPATIBILITY
# include "ruby/backward.h"
#endif

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 *
 * @internal
 *
 * Declaration of rb_struct_ptr() is at include/ruby/backward.h.
 */
#define RSTRUCT_PTR(st) rb_struct_ptr(st)
/** @cond INTERNAL_MACRO */
#define RSTRUCT_LEN RSTRUCT_LEN
#define RSTRUCT_SET RSTRUCT_SET
#define RSTRUCT_GET RSTRUCT_GET
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * Returns the number of struct members.
 *
 * @param[in]  st  An instance of RStruct.
 * @return     The number of members of `st`.
 * @pre        `st` must be of ::RUBY_T_STRUCT.
 */
VALUE rb_struct_size(VALUE st);

/**
 * Resembles `Struct#[]`.
 *
 * @param[in]  st              An instance of RStruct.
 * @param[in]  k               Index a.k.a. key of the struct.
 * @exception  rb_eTypeError   `k` is neither Numeric, Symbol, nor String.
 * @exception  rb_eIndexError  Numerical index out of range.
 * @exception  rb_eNameError   No such key.
 * @return     The member stored at `k` in `st`.
 * @pre        `st` must be of ::RUBY_T_STRUCT.
 */
VALUE rb_struct_aref(VALUE st, VALUE k);

/**
 * Resembles `Struct#[]=`.
 *
 * @param[out]  st              An instance of RStruct.
 * @param[in]   k               Index a.k.a. key of the struct.
 * @param[in]   v               Value to store.
 * @exception  rb_eTypeError    `k` is neither Numeric, Symbol, nor String.
 * @exception  rb_eIndexError   Numerical index out of range.
 * @exception  rb_eNameError    No such key.
 * @return     Passed `v`.
 * @pre        `st` must be of ::RUBY_T_STRUCT.
 * @post       `v` is stored at `k` in `st`.
 */
VALUE rb_struct_aset(VALUE st, VALUE k, VALUE v);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_ARTIFICIAL()
/** @copydoc rb_struct_size()  */
static inline long
RSTRUCT_LEN(VALUE st)
{
    RBIMPL_ASSERT_TYPE(st, RUBY_T_STRUCT);

    return RB_NUM2LONG(rb_struct_size(st));
}

RBIMPL_ATTR_ARTIFICIAL()
/** @copydoc rb_struct_aset()  */
static inline VALUE
RSTRUCT_SET(VALUE st, int k, VALUE v)
{
    RBIMPL_ASSERT_TYPE(st, RUBY_T_STRUCT);

    return rb_struct_aset(st, INT2NUM(k), (v));
}

RBIMPL_ATTR_ARTIFICIAL()
/** @copydoc rb_struct_aref()  */
static inline VALUE
RSTRUCT_GET(VALUE st, int k)
{
    RBIMPL_ASSERT_TYPE(st, RUBY_T_STRUCT);

    return rb_struct_aref(st, INT2NUM(k));
}

#endif /* RBIMPL_RSTRUCT_H */
