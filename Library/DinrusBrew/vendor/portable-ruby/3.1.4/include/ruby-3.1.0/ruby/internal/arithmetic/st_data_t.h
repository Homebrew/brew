#ifndef RBIMPL_ARITHMERIC_ST_DATA_T_H                /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMERIC_ST_DATA_T_H
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
 * @brief      Arithmetic conversion between C's `st_data_t` and Ruby's.
 */
#include "ruby/internal/arithmetic/fixnum.h"
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/value.h"
#include "ruby/assert.h"
#include "ruby/st.h"

#define ST2FIX    RB_ST2FIX     /**< @old{RB_ST2FIX} */
/** @cond INTERNAL_MACRO */
#define RB_ST2FIX RB_ST2FIX
/** @endcond */

RBIMPL_ATTR_CONST_UNLESS_DEBUG()
RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(CXX14)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Converts a C's `st_data_t` into an instance of ::rb_cInteger.
 *
 * @param[in]  i  The data in question.
 * @return     A converted result
 * @warning    THIS CONVERSION LOSES DATA!  Be warned.
 * @see        https://bugs.ruby-lang.org/issues/13877
 * @see        https://bugs.ruby-lang.org/issues/14218
 *
 * @internal
 *
 * This  is   needed  because  of   hash  functions.   Hash   functions  return
 * `st_data_t`,  which could  theoretically  be bigger  than Fixnums.   However
 * allocating Bignums for them every time  we calculate hash values is just too
 * heavy.  To avoid  penalty we need to  ignore some upper bit(s)  and stick to
 * Fixnums.  This function is used for that purpose.
 */
static inline VALUE
RB_ST2FIX(st_data_t i)
{
    SIGNED_VALUE x = i;

    if (x >= 0) {
        x &= RUBY_FIXNUM_MAX;
    }
    else {
        x |= RUBY_FIXNUM_MIN;
    }

    RBIMPL_ASSERT_OR_ASSUME(RB_FIXABLE(x));
    unsigned long y = RBIMPL_CAST((unsigned long)x);
    return RB_LONG2FIX(y);
}

#endif /* RBIMPL_ARITHMETIC_ST_DATA_T_H */
