#ifndef RBIMPL_RREGEXP_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RREGEXP_H
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
 * @brief      Defines struct ::RRegexp.
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/core/rstring.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"

/**
 * Convenient casting macro.
 *
 * @param   obj  An object, which is in fact an ::RRegexp.
 * @return  The passed object casted to ::RRegexp.
 */
#define RREGEXP(obj)     RBIMPL_CAST((struct RRegexp *)(obj))

/**
 * Convenient accessor macro.
 *
 * @param   obj  An object, which is in fact an ::RRegexp.
 * @return  The passed object's pattern buffer.
 */
#define RREGEXP_PTR(obj) (RREGEXP(obj)->ptr)
/** @cond INTERNAL_MACRO */
#define RREGEXP_SRC      RREGEXP_SRC
#define RREGEXP_SRC_PTR  RREGEXP_SRC_PTR
#define RREGEXP_SRC_LEN  RREGEXP_SRC_LEN
#define RREGEXP_SRC_END  RREGEXP_SRC_END
/** @endcond */

struct re_patter_buffer;  /* a.k.a. OnigRegexType, defined in onigmo.h */

/**
 * Ruby's regular expression.   A regexp is compiled into  its own intermediate
 * representation.  This  one holds that  info.  Regexp "match"  operation then
 * executes that IR.
 */
struct RRegexp {

    /** Basic part, including flags and class. */
    struct RBasic basic;

    /**
     * The pattern buffer.   This is a quasi-opaque struct  that holds compiled
     * intermediate representation of the regular expression.
     *
     * @note  Compilation of a regexp could be delayed until actual match.
     */
    struct re_pattern_buffer *ptr;

    /** Source code of this expression. */
    const VALUE src;

    /**
     * Reference count.  A  regexp match can take extraordinarily  long time to
     * run.  Ruby's  regular expression is  heavily extended and not  a regular
     * language any  longer; runs in NP-time  in practice.  Now, Ruby  also has
     * threads and GVL.  In order to prevent long GVL lockup, our regexp engine
     * can release it on occasions.  This means that multiple threads can touch
     * a regular expressions at once.  That  itself is okay.  But their cleanup
     * phase shall wait for all  the concurrent runs, to prevent use-after-free
     * situation.  This field is used to  count such threads that are executing
     * this particular pattern buffer.
     *
     * @warning  Of course, touching this field from extension libraries causes
     *           catastrophic effects.  Just leave it.
     */
    unsigned long usecnt;
};

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Convenient getter function.
 *
 * @param[in]  rexp  The regular expression in question.
 * @return     The source code of the regular expression.
 * @pre        `rexp` must be of ::RRegexp.
 */
static inline VALUE
RREGEXP_SRC(VALUE rexp)
{
    RBIMPL_ASSERT_TYPE(rexp, RUBY_T_REGEXP);
    VALUE ret = RREGEXP(rexp)->src;
    RBIMPL_ASSERT_TYPE(ret, RUBY_T_STRING);
    return ret;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Convenient getter function.
 *
 * @param[in]  rexp  The regular expression in question.
 * @return     The source code of the regular expression, in C's string.
 * @pre        `rexp` must be of ::RRegexp.
 *
 * @internal
 *
 * It seems nobody uses this function in the wild.  Subject to hide?
 */
static inline char *
RREGEXP_SRC_PTR(VALUE rexp)
{
    return RSTRING_PTR(RREGEXP_SRC(rexp));
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Convenient getter function.
 *
 * @param[in]  rexp  The regular expression in question.
 * @return     The length of the source code of the regular expression.
 * @pre        `rexp` must be of ::RRegexp.
 *
 * @internal
 *
 * It seems nobody uses this function in the wild.  Subject to hide?
 */
static inline long
RREGEXP_SRC_LEN(VALUE rexp)
{
    return RSTRING_LEN(RREGEXP_SRC(rexp));
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Convenient getter function.
 *
 * @param[in]  rexp  The regular expression in question.
 * @return     The end of the source code of the regular expression.
 * @pre        `rexp` must be of ::RRegexp.
 *
 * @internal
 *
 * It seems nobody uses this function in the wild.  Subject to hide?
 */
static inline char *
RREGEXP_SRC_END(VALUE rexp)
{
    return RSTRING_END(RREGEXP_SRC(rexp));
}

#endif /* RBIMPL_RREGEXP_H */
