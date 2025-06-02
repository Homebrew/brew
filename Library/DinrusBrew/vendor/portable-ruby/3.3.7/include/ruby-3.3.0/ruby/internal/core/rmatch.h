#ifndef RBIMPL_RMATCH_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RMATCH_H
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
 * @brief      Defines struct ::RMatch.
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/assert.h"

/**
 * Convenient casting macro.
 *
 * @param   obj  An object, which is in fact an ::RMatch.
 * @return  The passed object casted to ::RMatch.
 */
#define RMATCH(obj) RBIMPL_CAST((struct RMatch *)(obj))
/** @cond INTERNAL_MACRO */
#define RMATCH_REGS RMATCH_REGS
/** @endcond */

struct re_patter_buffer; /* a.k.a. OnigRegexType, defined in onigmo.h */
struct re_registers;     /* Also in onigmo.h */

/**
 * @old{re_pattern_buffer}
 *
 * @internal
 *
 * @shyouhei wonders: is anyone actively using this typedef ...?
 */
typedef struct re_pattern_buffer Regexp;

/**
 * Represents the  region of a  capture group.   This is basically  for caching
 * purpose.  re_registers have similar concepts  (`beg` and `end`) but they are
 * in `ptrdiff_t*`.  In order for  us to implement `MatchData#offset` that info
 * has to  be converted to  offset integers.  This is  the struct to  hold such
 * things.
 *
 * @internal
 *
 * But why on earth it has to be visible from extension libraries?
 */
struct rmatch_offset {
    long beg; /**< Beginning of a group. */
    long end; /**< End of a group. */
};

/** Represents a match. */
struct rb_matchext_struct {
    /**
     * "Registers"  of a  match.   This  is a  quasi-opaque  struct that  holds
     * execution result of a match.  Roughly resembles `&~`.
     */
    struct re_registers regs;

    /** Capture group offsets, in C array. */
    struct rmatch_offset *char_offset;

    /** Number of ::rmatch_offset that ::rmatch::char_offset holds. */
    int char_offset_num_allocated;
};

typedef struct rb_matchext_struct rb_matchext_t;

/**
 * Regular expression  execution context.  When a  regular expression "matches"
 * to a string, it generates capture  groups etc.  This struct holds that info.
 * Visible from Ruby as an instance of `MatchData`.
 *
 * @note  There is  no way  for extension libraries  to manually  generate this
 *        struct except by actually exercising the match operation of a regular
 *        expression.
 */
struct RMatch {

    /** Basic part, including flags and class. */
    struct RBasic basic;

    /**
     * The target string that the match was made against.
     */
    VALUE str;

    /**
     * The expression of this match.
     */
    VALUE regexp;  /* RRegexp */
};

#define RMATCH_EXT(m) ((rb_matchext_t *)((char *)(m) + sizeof(struct RMatch)))

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries the raw ::re_registers.
 *
 * @param[in]  match  A match object
 * @pre        `match` must be of ::RMatch.
 * @return     Its execution result.
 * @note       Good.  So you  are aware of the fact that  it could return NULL.
 *             Yes.  It  actually does.  This  is a really bizarre  thing.  The
 *             situation  is about  `String#gsub`  and its  family.  They  take
 *             strings as  arguments, like `"foo".sub("bar", "baz")`.   On such
 *             situations,  in  order  to optimise  memory  allocations,  these
 *             methods do  not involve regular  expressions at all.   They just
 *             sequentially scan  the receiver.  Okay.  The  story begins here.
 *             Even when  they do  not kick  our regexp  engine, there  must be
 *             backref objects e.g. `$&`.  But how?  You know what?  Ruby fakes
 *             them.  It  allocates an empty  ::RMatch and behaves as  if there
 *             were  execution   contexts.   In  reality  there   weren't.   No
 *             ::re_registers are  allocated then.   There is  no way  for this
 *             function but  to return NULL  for those fake ::RMatch.   This is
 *             the reason for the nullability of this function.
 */
static inline struct re_registers *
RMATCH_REGS(VALUE match)
{
    RBIMPL_ASSERT_TYPE(match, RUBY_T_MATCH);
    return &RMATCH_EXT(match)->regs;
}

#endif /* RBIMPL_RMATCH_H */
