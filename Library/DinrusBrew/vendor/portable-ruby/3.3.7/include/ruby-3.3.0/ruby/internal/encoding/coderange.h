#ifndef RUBY_INTERNAL_ENCODING_CODERANGE_H           /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_CODERANGE_H
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
 * @brief      Routines for code ranges.
 */

#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/** What rb_enc_str_coderange() returns. */
enum ruby_coderange_type {

    /** The object's coderange is unclear yet. */
    RUBY_ENC_CODERANGE_UNKNOWN  = 0,

    /** The object holds 0 to 127 inclusive and nothing else. */
    RUBY_ENC_CODERANGE_7BIT     = ((int)RUBY_FL_USER8),

    /** The object's encoding and contents are consistent each other */
    RUBY_ENC_CODERANGE_VALID    = ((int)RUBY_FL_USER9),

    /** The object holds invalid/malformed/broken character(s). */
    RUBY_ENC_CODERANGE_BROKEN   = ((int)(RUBY_FL_USER8|RUBY_FL_USER9)),

    /** Where the coderange resides. */
    RUBY_ENC_CODERANGE_MASK     = (RUBY_ENC_CODERANGE_7BIT|
                                   RUBY_ENC_CODERANGE_VALID|
                                   RUBY_ENC_CODERANGE_BROKEN)
};

RBIMPL_ATTR_CONST()
/**
 * @private
 *
 * This is an implementation detail of #RB_ENC_CODERANGE_CLEAN_P.  People don't
 * use it directly.
 *
 * @param[in]  cr  An enum ::ruby_coderange_type.
 * @retval     1   It is.
 * @retval     0   It isn't.
 */
static inline int
rb_enc_coderange_clean_p(int cr)
{
    return (cr ^ (cr >> 1)) & RUBY_ENC_CODERANGE_7BIT;
}

RBIMPL_ATTR_CONST()
/**
 * Queries if  a code range  is "clean".  "Clean" in  this context means  it is
 * known and valid.
 *
 * @param[in]  cr  An enum ::ruby_coderange_type.
 * @retval     1   It is.
 * @retval     0   It isn't.
 */
static inline bool
RB_ENC_CODERANGE_CLEAN_P(enum ruby_coderange_type cr)
{
    return rb_enc_coderange_clean_p(cr);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/**
 * Queries the  (inline) code range of  the passed object.  The  object must be
 * capable  of   having  inline   encoding.   Using   this  macro   needs  deep
 * understanding of bit level object binary layout.
 *
 * @param[in]  obj  Target object.
 * @return     An enum ::ruby_coderange_type.
 */
static inline enum ruby_coderange_type
RB_ENC_CODERANGE(VALUE obj)
{
    VALUE ret = RB_FL_TEST_RAW(obj, RUBY_ENC_CODERANGE_MASK);

    return RBIMPL_CAST((enum ruby_coderange_type)ret);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/**
 * Queries   the    (inline)   code   range    of   the   passed    object   is
 * ::RUBY_ENC_CODERANGE_7BIT.   The object  must  be capable  of having  inline
 * encoding.  Using  this macro  needs deep understanding  of bit  level object
 * binary layout.
 *
 * @param[in]  obj  Target object.
 * @retval     1    It is ascii only.
 * @retval     0    Otherwise (including cases when the range is not known).
 */
static inline bool
RB_ENC_CODERANGE_ASCIIONLY(VALUE obj)
{
    return RB_ENC_CODERANGE(obj) == RUBY_ENC_CODERANGE_7BIT;
}

/**
 * Destructively modifies the passed object so  that its (inline) code range is
 * the  passed one.   The object  must be  capable of  having inline  encoding.
 * Using this macro needs deep understanding of bit level object binary layout.
 *
 * @param[out]  obj  Target object.
 * @param[out]  cr   An enum ::ruby_coderange_type.
 * @post        `obj`'s code range is `cr`.
 */
static inline void
RB_ENC_CODERANGE_SET(VALUE obj, enum ruby_coderange_type cr)
{
    RB_FL_UNSET_RAW(obj, RUBY_ENC_CODERANGE_MASK);
    RB_FL_SET_RAW(obj, cr);
}

/**
 * Destructively clears  the passed object's  (inline) code range.   The object
 * must be  capable of  having inline  encoding.  Using  this macro  needs deep
 * understanding of bit level object binary layout.
 *
 * @param[out]  obj  Target object.
 * @post        `obj`'s code range is ::RUBY_ENC_CODERANGE_UNKNOWN.
 */
static inline void
RB_ENC_CODERANGE_CLEAR(VALUE obj)
{
    RB_FL_UNSET_RAW(obj, RUBY_ENC_CODERANGE_MASK);
}

RBIMPL_ATTR_CONST()
/* assumed ASCII compatibility */
/**
 * "Mix"  two code  ranges  into one.   This  is handy  for  instance when  you
 * concatenate two  strings into one.   Consider one of  then is valid  but the
 * other isn't.  The result must be  invalid.  This macro computes that kind of
 * mixture.
 *
 * @param[in]  a  An enum ::ruby_coderange_type.
 * @param[in]  b  Another enum ::ruby_coderange_type.
 * @return     The `a` "and" `b`.
 */
static inline enum ruby_coderange_type
RB_ENC_CODERANGE_AND(enum ruby_coderange_type a, enum ruby_coderange_type b)
{
    if (a == RUBY_ENC_CODERANGE_7BIT) {
        return b;
    }
    else if (a != RUBY_ENC_CODERANGE_VALID) {
        return RUBY_ENC_CODERANGE_UNKNOWN;
    }
    else if (b == RUBY_ENC_CODERANGE_7BIT) {
        return RUBY_ENC_CODERANGE_VALID;
    }
    else {
        return b;
    }
}

#define ENC_CODERANGE_MASK                        RUBY_ENC_CODERANGE_MASK                      /**< @old{RUBY_ENC_CODERANGE_MASK} */
#define ENC_CODERANGE_UNKNOWN                     RUBY_ENC_CODERANGE_UNKNOWN                   /**< @old{RUBY_ENC_CODERANGE_UNKNOWN} */
#define ENC_CODERANGE_7BIT                        RUBY_ENC_CODERANGE_7BIT                      /**< @old{RUBY_ENC_CODERANGE_7BIT} */
#define ENC_CODERANGE_VALID                       RUBY_ENC_CODERANGE_VALID                     /**< @old{RUBY_ENC_CODERANGE_VALID} */
#define ENC_CODERANGE_BROKEN                      RUBY_ENC_CODERANGE_BROKEN                    /**< @old{RUBY_ENC_CODERANGE_BROKEN} */
#define ENC_CODERANGE_CLEAN_P(cr)                 RB_ENC_CODERANGE_CLEAN_P(cr)                 /**< @old{RB_ENC_CODERANGE_CLEAN_P} */
#define ENC_CODERANGE(obj)                        RB_ENC_CODERANGE(obj)                        /**< @old{RB_ENC_CODERANGE} */
#define ENC_CODERANGE_ASCIIONLY(obj)              RB_ENC_CODERANGE_ASCIIONLY(obj)              /**< @old{RB_ENC_CODERANGE_ASCIIONLY} */
#define ENC_CODERANGE_SET(obj,cr)                 RB_ENC_CODERANGE_SET(obj,cr)                 /**< @old{RB_ENC_CODERANGE_SET} */
#define ENC_CODERANGE_CLEAR(obj)                  RB_ENC_CODERANGE_CLEAR(obj)                  /**< @old{RB_ENC_CODERANGE_CLEAR} */
#define ENC_CODERANGE_AND(a, b)                   RB_ENC_CODERANGE_AND(a, b)                   /**< @old{RB_ENC_CODERANGE_AND} */
#define ENCODING_CODERANGE_SET(obj, encindex, cr) RB_ENCODING_CODERANGE_SET(obj, encindex, cr) /**< @old{RB_ENCODING_CODERANGE_SET} */

/** @cond INTERNAL_MACRO */
#define RB_ENC_CODERANGE           RB_ENC_CODERANGE
#define RB_ENC_CODERANGE_AND       RB_ENC_CODERANGE_AND
#define RB_ENC_CODERANGE_ASCIIONLY RB_ENC_CODERANGE_ASCIIONLY
#define RB_ENC_CODERANGE_CLEAN_P   RB_ENC_CODERANGE_CLEAN_P
#define RB_ENC_CODERANGE_CLEAR     RB_ENC_CODERANGE_CLEAR
#define RB_ENC_CODERANGE_SET       RB_ENC_CODERANGE_SET
/** @endcond */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_CODERANGE_H */
