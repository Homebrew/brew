#ifndef RBIMPL_ARITHMETIC_OFF_T_H                    /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_OFF_T_H
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
 * @brief      Arithmetic conversion between C's `off_t` and Ruby's.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/arithmetic/int.h"
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/arithmetic/long_long.h"
#include "ruby/backward/2/long_long.h"

/** Converts a C's `off_t` into an instance of ::rb_cInteger. */
#ifdef OFFT2NUM
# /* take that. */
#elif SIZEOF_OFF_T == SIZEOF_LONG_LONG
# define OFFT2NUM RB_LL2NUM
#elif SIZEOF_OFF_T == SIZEOF_LONG
# define OFFT2NUM RB_LONG2NUM
#else
# define OFFT2NUM RB_INT2NUM
#endif

/** Converts an instance of ::rb_cNumeric into C's `off_t`. */
#ifdef NUM2OFFT
# /* take that. */
#elif SIZEOF_OFF_T == SIZEOF_LONG_LONG
# define NUM2OFFT RB_NUM2LL
#elif SIZEOF_OFF_T == SIZEOF_LONG
# define NUM2OFFT RB_NUM2LONG
#else
# define NUM2OFFT RB_NUM2INT
#endif

/** A rb_sprintf() format prefix to be used for an `off_t` parameter. */
#ifdef PRI_OFFT_PREFIX
# /* take that. */
#elif SIZEOF_OFF_T == SIZEOF_LONG_LONG
# define PRI_OFFT_PREFIX PRI_LL_PREFIX
#elif SIZEOF_OFF_T == SIZEOF_LONG
# define PRI_OFFT_PREFIX PRI_LONG_PREFIX
#else
# define PRI_OFFT_PREFIX PRI_INT_PREFIX
#endif

#endif /* RBIMPL_ARITHMETIC_OFF_T_H */
