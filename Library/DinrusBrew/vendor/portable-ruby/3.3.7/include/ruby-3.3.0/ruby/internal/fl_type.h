#ifndef RBIMPL_FL_TYPE_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_FL_TYPE_H
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
 * @brief      Defines enum ::ruby_fl_type.
 */
#include "ruby/internal/config.h"      /* for ENUM_OVER_INT */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/flag_enum.h"
#include "ruby/internal/attr/forceinline.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/has/extension.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/assert.h"
#include "ruby/defines.h"

/** @cond INTERNAL_MACRO */
#if RBIMPL_HAS_EXTENSION(enumerator_attributes)
# define RBIMPL_HAVE_ENUM_ATTRIBUTE 1
#elif RBIMPL_COMPILER_SINCE(GCC, 6, 0, 0)
# define RBIMPL_HAVE_ENUM_ATTRIBUTE 1
#endif

#ifdef ENUM_OVER_INT
# define RBIMPL_WIDER_ENUM 1
#elif SIZEOF_INT * CHAR_BIT > 12+19+1
# define RBIMPL_WIDER_ENUM 1
#else
# define RBIMPL_WIDER_ENUM 0
#endif
/** @endcond */

#define FL_SINGLETON    RBIMPL_CAST((VALUE)RUBY_FL_SINGLETON)            /**< @old{RUBY_FL_SINGLETON} */
#define FL_WB_PROTECTED RBIMPL_CAST((VALUE)RUBY_FL_WB_PROTECTED)         /**< @old{RUBY_FL_WB_PROTECTED} */
#define FL_PROMOTED     RBIMPL_CAST((VALUE)RUBY_FL_PROMOTED)             /**< @old{RUBY_FL_PROMOTED} */
#define FL_FINALIZE     RBIMPL_CAST((VALUE)RUBY_FL_FINALIZE)             /**< @old{RUBY_FL_FINALIZE} */
#define FL_TAINT        RBIMPL_CAST((VALUE)RUBY_FL_TAINT)                /**< @old{RUBY_FL_TAINT} */
#define FL_SHAREABLE    RBIMPL_CAST((VALUE)RUBY_FL_SHAREABLE)            /**< @old{RUBY_FL_SHAREABLE} */
#define FL_UNTRUSTED    RBIMPL_CAST((VALUE)RUBY_FL_UNTRUSTED)            /**< @old{RUBY_FL_UNTRUSTED} */
#define FL_SEEN_OBJ_ID  RBIMPL_CAST((VALUE)RUBY_FL_SEEN_OBJ_ID)          /**< @old{RUBY_FL_SEEN_OBJ_ID} */
#define FL_EXIVAR       RBIMPL_CAST((VALUE)RUBY_FL_EXIVAR)               /**< @old{RUBY_FL_EXIVAR} */
#define FL_FREEZE       RBIMPL_CAST((VALUE)RUBY_FL_FREEZE)               /**< @old{RUBY_FL_FREEZE} */

#define FL_USHIFT       RBIMPL_CAST((VALUE)RUBY_FL_USHIFT)               /**< @old{RUBY_FL_USHIFT} */

#define FL_USER0        RBIMPL_CAST((VALUE)RUBY_FL_USER0)                /**< @old{RUBY_FL_USER0} */
#define FL_USER1        RBIMPL_CAST((VALUE)RUBY_FL_USER1)                /**< @old{RUBY_FL_USER1} */
#define FL_USER2        RBIMPL_CAST((VALUE)RUBY_FL_USER2)                /**< @old{RUBY_FL_USER2} */
#define FL_USER3        RBIMPL_CAST((VALUE)RUBY_FL_USER3)                /**< @old{RUBY_FL_USER3} */
#define FL_USER4        RBIMPL_CAST((VALUE)RUBY_FL_USER4)                /**< @old{RUBY_FL_USER4} */
#define FL_USER5        RBIMPL_CAST((VALUE)RUBY_FL_USER5)                /**< @old{RUBY_FL_USER5} */
#define FL_USER6        RBIMPL_CAST((VALUE)RUBY_FL_USER6)                /**< @old{RUBY_FL_USER6} */
#define FL_USER7        RBIMPL_CAST((VALUE)RUBY_FL_USER7)                /**< @old{RUBY_FL_USER7} */
#define FL_USER8        RBIMPL_CAST((VALUE)RUBY_FL_USER8)                /**< @old{RUBY_FL_USER8} */
#define FL_USER9        RBIMPL_CAST((VALUE)RUBY_FL_USER9)                /**< @old{RUBY_FL_USER9} */
#define FL_USER10       RBIMPL_CAST((VALUE)RUBY_FL_USER10)               /**< @old{RUBY_FL_USER10} */
#define FL_USER11       RBIMPL_CAST((VALUE)RUBY_FL_USER11)               /**< @old{RUBY_FL_USER11} */
#define FL_USER12       RBIMPL_CAST((VALUE)RUBY_FL_USER12)               /**< @old{RUBY_FL_USER12} */
#define FL_USER13       RBIMPL_CAST((VALUE)RUBY_FL_USER13)               /**< @old{RUBY_FL_USER13} */
#define FL_USER14       RBIMPL_CAST((VALUE)RUBY_FL_USER14)               /**< @old{RUBY_FL_USER14} */
#define FL_USER15       RBIMPL_CAST((VALUE)RUBY_FL_USER15)               /**< @old{RUBY_FL_USER15} */
#define FL_USER16       RBIMPL_CAST((VALUE)RUBY_FL_USER16)               /**< @old{RUBY_FL_USER16} */
#define FL_USER17       RBIMPL_CAST((VALUE)RUBY_FL_USER17)               /**< @old{RUBY_FL_USER17} */
#define FL_USER18       RBIMPL_CAST((VALUE)RUBY_FL_USER18)               /**< @old{RUBY_FL_USER18} */
#define FL_USER19       RBIMPL_CAST((VALUE)(unsigned int)RUBY_FL_USER19) /**< @old{RUBY_FL_USER19} */

#define ELTS_SHARED          RUBY_ELTS_SHARED     /**< @old{RUBY_ELTS_SHARED} */
#define RB_OBJ_FREEZE        rb_obj_freeze_inline /**< @alias{rb_obj_freeze_inline} */

/** @cond INTERNAL_MACRO */
#define RUBY_ELTS_SHARED     RUBY_ELTS_SHARED
#define RB_FL_ABLE           RB_FL_ABLE
#define RB_FL_ALL            RB_FL_ALL
#define RB_FL_ALL_RAW        RB_FL_ALL_RAW
#define RB_FL_ANY            RB_FL_ANY
#define RB_FL_ANY_RAW        RB_FL_ANY_RAW
#define RB_FL_REVERSE        RB_FL_REVERSE
#define RB_FL_REVERSE_RAW    RB_FL_REVERSE_RAW
#define RB_FL_SET            RB_FL_SET
#define RB_FL_SET_RAW        RB_FL_SET_RAW
#define RB_FL_TEST           RB_FL_TEST
#define RB_FL_TEST_RAW       RB_FL_TEST_RAW
#define RB_FL_UNSET          RB_FL_UNSET
#define RB_FL_UNSET_RAW      RB_FL_UNSET_RAW
#define RB_OBJ_FREEZE_RAW    RB_OBJ_FREEZE_RAW
#define RB_OBJ_FROZEN        RB_OBJ_FROZEN
#define RB_OBJ_FROZEN_RAW    RB_OBJ_FROZEN_RAW
#define RB_OBJ_UNTRUST       RB_OBJ_TAINT
#define RB_OBJ_UNTRUSTED     RB_OBJ_TAINTED
/** @endcond */

/**
 * @defgroup deprecated_macros Deprecated macro APIs
 * @{
 * These macros are deprecated.  Prefer their `RB_`-prefixed versions.
 */
#define FL_ABLE         RB_FL_ABLE         /**< @old{RB_FL_ABLE} */
#define FL_ALL          RB_FL_ALL          /**< @old{RB_FL_ALL} */
#define FL_ALL_RAW      RB_FL_ALL_RAW      /**< @old{RB_FL_ALL_RAW} */
#define FL_ANY          RB_FL_ANY          /**< @old{RB_FL_ANY} */
#define FL_ANY_RAW      RB_FL_ANY_RAW      /**< @old{RB_FL_ANY_RAW} */
#define FL_REVERSE      RB_FL_REVERSE      /**< @old{RB_FL_REVERSE} */
#define FL_REVERSE_RAW  RB_FL_REVERSE_RAW  /**< @old{RB_FL_REVERSE_RAW} */
#define FL_SET          RB_FL_SET          /**< @old{RB_FL_SET} */
#define FL_SET_RAW      RB_FL_SET_RAW      /**< @old{RB_FL_SET_RAW} */
#define FL_TEST         RB_FL_TEST         /**< @old{RB_FL_TEST} */
#define FL_TEST_RAW     RB_FL_TEST_RAW     /**< @old{RB_FL_TEST_RAW} */
#define FL_UNSET        RB_FL_UNSET        /**< @old{RB_FL_UNSET} */
#define FL_UNSET_RAW    RB_FL_UNSET_RAW    /**< @old{RB_FL_UNSET_RAW} */
#define OBJ_FREEZE      RB_OBJ_FREEZE      /**< @old{RB_OBJ_FREEZE} */
#define OBJ_FREEZE_RAW  RB_OBJ_FREEZE_RAW  /**< @old{RB_OBJ_FREEZE_RAW} */
#define OBJ_FROZEN      RB_OBJ_FROZEN      /**< @old{RB_OBJ_FROZEN} */
#define OBJ_FROZEN_RAW  RB_OBJ_FROZEN_RAW  /**< @old{RB_OBJ_FROZEN_RAW} */
#define OBJ_INFECT      RB_OBJ_INFECT      /**< @old{RB_OBJ_INFECT} */
#define OBJ_INFECT_RAW  RB_OBJ_INFECT_RAW  /**< @old{RB_OBJ_INFECT_RAW} */
#define OBJ_TAINT       RB_OBJ_TAINT       /**< @old{RB_OBJ_TAINT} */
#define OBJ_TAINTABLE   RB_OBJ_TAINTABLE   /**< @old{RB_OBJ_TAINT_RAW} */
#define OBJ_TAINTED     RB_OBJ_TAINTED     /**< @old{RB_OBJ_TAINTED} */
#define OBJ_TAINTED_RAW RB_OBJ_TAINTED_RAW /**< @old{RB_OBJ_TAINTED_RAW} */
#define OBJ_TAINT_RAW   RB_OBJ_TAINT_RAW   /**< @old{RB_OBJ_TAINT_RAW} */
#define OBJ_UNTRUST     RB_OBJ_UNTRUST     /**< @old{RB_OBJ_TAINT} */
#define OBJ_UNTRUSTED   RB_OBJ_UNTRUSTED   /**< @old{RB_OBJ_TAINTED} */
/** @} */

/**
 * This is an enum because GDB wants it (rather than a macro).  People need not
 * bother.
 */
enum ruby_fl_ushift {
    /**
     * Number of bits in ::ruby_fl_type that  are _not_ open to users.  This is
     * an implementation detail.  Please ignore.
     */
    RUBY_FL_USHIFT = 12
};

/* > The expression that defines the value  of an enumeration constant shall be
 * > an integer constant expression that has a value representable as an `int`.
 *
 * -- ISO/IEC 9899:2018 section 6.7.2.2
 *
 * So ENUM_OVER_INT  situation is an  extension to the standard.   Note however
 * that we do not support 16 bit `int` environment. */
RB_GNUC_EXTENSION
/**
 * The  flags.  Each  ruby objects  have their  own characteristics  apart from
 * their  classes.  For  instance whether  an object  is frozen  or not  is not
 * controlled by its class.  This is the type that represents such properties.
 *
 * @note  About the `FL_USER` terminology: the "user" here does not necessarily
 *        mean only  you.  For  instance struct  ::RString instances  use these
 *        bits to cache their encodings  etc.  Devs discussed about this topic,
 *        reached their  consensus that  ::RUBY_T_DATA is  the only  valid data
 *        structure that  can use these  bits; other data  structures including
 *        ::RUBY_T_OBJECT  use these  bits  for their  own  purpose.  See  also
 *        https://bugs.ruby-lang.org/issues/18059
 */
enum
RBIMPL_ATTR_FLAG_ENUM()
ruby_fl_type {

    /**
     * @deprecated  This flag once was a thing  back in the old days, but makes
     *              no  sense  any longer  today.   Exists  here for  backwards
     *              compatibility only.  You can safely forget about it.
     *
     * @internal
     *
     * The reality is our GC no  longer remembers write barriers inside of each
     * objects, to use  dedicated bitmap instead.  But this flag  is still used
     * internally.   The  current  usages  of this  flag  should  be  something
     * different, which is unclear to @shyouhei.
     */
    RUBY_FL_WB_PROTECTED = (1<<5),

    /**
     * Ruby objects are "generational".  There are young objects & old objects.
     * Young objects are prone to die & monitored relatively extensively by the
     * garbage collector.  Old objects tend to live longer & are monitored less
     * frequently.  When an object survives a GC, its age is incremented.  When
     * age is equal to RVALUE_OLD_AGE, the object becomes Old. This flag is set
     * when an object becomes old, and is used by the write barrier to check if
     * an old object should be considered for marking more frequently  - as old
     * objects that have references added between major GCs need to be remarked
     * to prevent the referred object being mistakenly swept.
     *
     * @internal
     *
     * But honestly, @shyouhei  doesn't think this flag should  be visible from
     * 3rd parties.  It must be an implementation detail that they should never
     * know.  Might better be hidden.
     */
    RUBY_FL_PROMOTED    = (1<<5),

    /**
     * This flag is no longer in use
     *
     * @internal
     */
    RUBY_FL_UNUSED6    = (1<<6),

    /**
     * This flag has  something to do with finalisers.  A  ruby object can have
     * its finaliser,  which is another  object that evaluates when  the target
     * object is about  to die.  This flag  is used to denote that  there is an
     * attached finaliser.
     *
     * @internal
     *
     * But honestly, @shyouhei  doesn't think this flag should  be visible from
     * 3rd parties.  It must be an implementation detail that they should never
     * know.  Might better be hidden.
     */
    RUBY_FL_FINALIZE     = (1<<7),

    /**
     * @deprecated  This flag once was a thing  back in the old days, but makes
     *              no  sense  any longer  today.   Exists  here for  backwards
     *              compatibility only.  You can safely forget about it.
     */
    RUBY_FL_TAINT

#if defined(RBIMPL_HAVE_ENUM_ATTRIBUTE)
    RBIMPL_ATTR_DEPRECATED(("taintedness turned out to be a wrong idea."))
#elif defined(_MSC_VER)
# pragma deprecated(RUBY_FL_TAINT)
#endif

                         = 0,

    /**
     * This flag has something to do with Ractor.  Multiple Ractors run without
     * protecting each  other.  Sharing an  object among Ractors  are basically
     * dangerous,  disabled by  default.   This  flag is  used  to bypass  that
     * restriction.  Of  course, you have  to manually prevent  race conditions
     * then.
     *
     * This flag  needs deep  understanding of multithreaded  programming.  You
     * would better not use it.
     */
    RUBY_FL_SHAREABLE    = (1<<8),

    /**
     * @deprecated  This flag once was a thing  back in the old days, but makes
     *              no  sense  any longer  today.   Exists  here for  backwards
     *              compatibility only.  You can safely forget about it.
     */
    RUBY_FL_UNTRUSTED

#if defined(RBIMPL_HAVE_ENUM_ATTRIBUTE)
    RBIMPL_ATTR_DEPRECATED(("trustedness turned out to be a wrong idea."))
#elif defined(_MSC_VER)
# pragma deprecated(RUBY_FL_UNTRUSTED)
#endif

                         = 0,

    /**
     * This flag has something to do with  object IDs.  Unlike in the old days,
     * an object's object  ID (that a user can  query using `Object#object_id`)
     * is no longer its physical address represented using Ruby level integers.
     * It is  now a  monotonic-increasing integer  unrelated to  the underlying
     * memory arrangement.  Object IDs are assigned when necessary; objects are
     * born without one,  and will eventually have such  property when queried.
     * The interpreter has to manage which one is which.  This is the flag that
     * helps the  management.  Objects  with this  flag set  are the  ones with
     * object IDs assigned.
     *
     * @internal
     *
     * But honestly, @shyouhei  doesn't think this flag should  be visible from
     * 3rd parties.  It must be an implementation detail that they should never
     * know.  Might better be hidden.
     */
    RUBY_FL_SEEN_OBJ_ID  = (1<<9),

    /**
     * This flag has something to do with instance variables.  3rd parties need
     * not  know, but  there are  several ways  to store  an object's  instance
     * variables.   Objects  with this  flag  use  so-called "generic"  backend
     * storage.  This  distinction is purely an  implementation detail.  People
     * need not be aware of this working behind-the-scene.
     *
     * @internal
     *
     * As of writing everything except ::RObject and RModule use this scheme.
     */
    RUBY_FL_EXIVAR       = (1<<10),

    /**
     * This flag has something to do with data immutability.  When this flag is
     * set an object  is considered "frozen".  No modification  are expected to
     * happen beyond  that point  for the  particular object.   Immutability is
     * basically considered to be a  good property these days.  Library authors
     * are expected to obey.  Test this bit before you touch a data structure.
     *
     * @see rb_check_frozen()
     */
    RUBY_FL_FREEZE       = (1<<11),

/** (@shyouhei doesn't know how to excude this macro from doxygen). */
#define RBIMPL_FL_USER_N(n) RUBY_FL_USER##n = (1<<(RUBY_FL_USHIFT+n))
    RBIMPL_FL_USER_N(0),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(1),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(2),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(3),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(4),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(5),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(6),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(7),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(8),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(9),  /**< User-defined flag. */
    RBIMPL_FL_USER_N(10), /**< User-defined flag. */
    RBIMPL_FL_USER_N(11), /**< User-defined flag. */
    RBIMPL_FL_USER_N(12), /**< User-defined flag. */
    RBIMPL_FL_USER_N(13), /**< User-defined flag. */
    RBIMPL_FL_USER_N(14), /**< User-defined flag. */
    RBIMPL_FL_USER_N(15), /**< User-defined flag. */
    RBIMPL_FL_USER_N(16), /**< User-defined flag. */
    RBIMPL_FL_USER_N(17), /**< User-defined flag. */
    RBIMPL_FL_USER_N(18), /**< User-defined flag. */
#ifdef ENUM_OVER_INT
    RBIMPL_FL_USER_N(19), /**< User-defined flag. */
#else
# define RUBY_FL_USER19 (RBIMPL_VALUE_ONE<<(RUBY_FL_USHIFT+19))
#endif
#undef RBIMPL_FL_USER_N
#undef RBIMPL_WIDER_ENUM

    /**
     * This flag  has something to  do with  data structures.  Over  time, ruby
     * evolved to reduce  memory footprints.  One of such  attempt is so-called
     * copy-on-write, which  delays duplication  of resources  until ultimately
     * necessary.   Some  data  structures  share  this  scheme.   For  example
     * multiple  instances  of struct  ::RArray  could  point identical  memory
     * region  in common,  as  long as  they don't  differ.   As people  favour
     * immutable style  of programming than  before, this situation  is getting
     * more and more common.  Because such "shared" memory regions have nuanced
     * ownership by nature,  each structures need special care  for them.  This
     * flag is used to distinguish such shared constructs.
     *
     * @internal
     *
     * But honestly, @shyouhei  doesn't think this flag should  be visible from
     * 3rd parties.  It must be an implementation detail that they should never
     * know.  Might better be hidden.
     */
    RUBY_ELTS_SHARED  = RUBY_FL_USER2,

    /**
     * This flag has something to do with an object's class.  There are kind of
     * classes  called  "singleton  class",  each of  which  have  exactly  one
     * instance.  What is interesting about  singleton classes is that they are
     * created _after_ their instance were instantiated, like this:
     *
     * ```ruby
     * foo = Object.new          # foo is an instance of Object...
     * bar = foo.singleton_class # foo is now an instance of bar.
     * ```
     *
     * Here as you see  `bar` is a singleton class of  `foo`, which is injected
     * into  `foo`'s inheritance  tree in  a different  statement (==  distinct
     * sequence point).   In order to  achieve this property  singleton classes
     * are  special-cased in  the  interpreter.   There is  one  bit flag  that
     * distinguishes if a class is a singleton class or not, and this is it.
     *
     * @internal
     *
     * But honestly, @shyouhei  doesn't think this flag should  be visible from
     * 3rd parties.  It must be an implementation detail that they should never
     * know.  Might better be hidden.
     */
    RUBY_FL_SINGLETON = RUBY_FL_USER0,
};

enum {
    /**
     * @deprecated  This flag once was a thing  back in the old days, but makes
     *              no  sense  any longer  today.   Exists  here for  backwards
     *              compatibility only.  You can safely forget about it.
     */
    RUBY_FL_DUPPED

#if defined(RBIMPL_HAVE_ENUM_ATTRIBUTE)
    RBIMPL_ATTR_DEPRECATED(("It seems there is no actual usage of this enum."))
#elif defined(_MSC_VER)
# pragma deprecated(RUBY_FL_DUPPED)
#endif

    = (int)RUBY_T_MASK | (int)RUBY_FL_EXIVAR
};

#undef RBIMPL_HAVE_ENUM_ATTRIBUTE

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * This is an  implementation detail of #RB_OBJ_FREEZE().  People  don't use it
 * directly.
 *
 * @param[out]  klass  A singleton class.
 * @post        `klass` gets frozen.
 */
void rb_freeze_singleton_class(VALUE klass);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_FORCEINLINE()
/**
 * Checks  if the  object is  flaggable.  There  are some  special cases  (most
 * notably ::RUBY_Qfalse) where appending a flag  to an object is not possible.
 * This function can detect that.
 *
 * @param[in]  obj    Object in question
 * @retval     true   It is flaggable.
 * @retval     false  No it isn't.
 */
static bool
RB_FL_ABLE(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else if (RB_TYPE_P(obj, RUBY_T_NODE)) {
        return false;
    }
    else {
        return true;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * This is an implementation detail of  RB_FL_TEST().  3rd parties need not use
 * this.  Just always use RB_FL_TEST().
 *
 * @param[in]  obj    Object in question.
 * @param[in]  flags  A set of enum ::ruby_fl_type.
 * @pre        The object must not be an enum ::ruby_special_consts.
 * @return     `obj`'s flags, masked by `flags`.
 */
static inline VALUE
RB_FL_TEST_RAW(VALUE obj, VALUE flags)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    return RBASIC(obj)->flags & flags;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Tests if the given  flag(s) are set or not.  You can  pass multiple flags at
 * once:
 *
 * ```CXX
 * auto obj = rb_eval_string("...");
 * if (RB_FL_TEST(obj, RUBY_FL_FREEZE | RUBY_FL_SHAREABLE)) {
 *     printf("Ractor ready!\n");
 * }
 * ```
 *
 * @param[in]  obj    Object in question.
 * @param[in]  flags  A set of enum ::ruby_fl_type.
 * @return     `obj`'s flags, masked by `flags`.
 * @note       It  is intentional  for this  function to  return ::VALUE.   The
 *             return value could be passed to RB_FL_STE() etc.
 */
static inline VALUE
RB_FL_TEST(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        return RB_FL_TEST_RAW(obj, flags);
    }
    else {
        return RBIMPL_VALUE_NULL;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * This is an  implementation detail of RB_FL_ANY().  3rd parties  need not use
 * this.  Just always use RB_FL_ANY().
 *
 * @param[in]  obj    Object in question.
 * @param[in]  flags  A set of enum ::ruby_fl_type.
 * @retval     true   The object has any of the flags set.
 * @retval     false  No it doesn't at all.
 * @pre        The object must not be an enum ::ruby_special_consts.
 */
static inline bool
RB_FL_ANY_RAW(VALUE obj, VALUE flags)
{
    return RB_FL_TEST_RAW(obj, flags);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Identical to RB_FL_TEST(), except it returns bool.
 *
 * @param[in]  obj    Object in question.
 * @param[in]  flags  A set of enum ::ruby_fl_type.
 * @retval     true   The object has any of the flags set.
 * @retval     false  No it doesn't at all.
 */
static inline bool
RB_FL_ANY(VALUE obj, VALUE flags)
{
    return RB_FL_TEST(obj, flags);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * This is an  implementation detail of RB_FL_ALL().  3rd parties  need not use
 * this.  Just always use RB_FL_ALL().
 *
 * @param[in]  obj    Object in question.
 * @param[in]  flags  A set of enum ::ruby_fl_type.
 * @retval     true   The object has all of the flags set.
 * @retval     false  The object lacks any of the flags.
 * @pre        The object must not be an enum ::ruby_special_consts.
 */
static inline bool
RB_FL_ALL_RAW(VALUE obj, VALUE flags)
{
    return RB_FL_TEST_RAW(obj, flags) == flags;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Identical to RB_FL_ANY(), except it mandates all passed flags be set.
 *
 * @param[in]  obj    Object in question.
 * @param[in]  flags  A set of enum ::ruby_fl_type.
 * @retval     true   The object has all of the flags set.
 * @retval     false  The object lacks any of the flags.
 */
static inline bool
RB_FL_ALL(VALUE obj, VALUE flags)
{
    return RB_FL_TEST(obj, flags) == flags;
}

RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * @private
 *
 * This is an  implementation detail of RB_FL_SET().  3rd parties  need not use
 * this.  Just always use RB_FL_SET().
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` set.
 *
 * @internal
 *
 * This  is  function  is  here  to  annotate  a  part  of  RB_FL_SET_RAW()  as
 * `__declspec(noalias)`.
 */
static inline void
rbimpl_fl_set_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags |= flags;
}

RBIMPL_ATTR_ARTIFICIAL()
/**
 * This is an  implementation detail of RB_FL_SET().  3rd parties  need not use
 * this.  Just always use RB_FL_SET().
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` set.
 */
static inline void
RB_FL_SET_RAW(VALUE obj, VALUE flags)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    rbimpl_fl_set_raw_raw(RBASIC(obj), flags);
}

RBIMPL_ATTR_ARTIFICIAL()
/**
 * Sets the given flag(s).
 *
 * ```CXX
 * auto v = rb_eval_string("...");
 * RB_FL_SET(v, RUBY_FL_FREEZE);
 * ```
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` set.
 */
static inline void
RB_FL_SET(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_SET_RAW(obj, flags);
    }
}

RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * @private
 *
 * This is an implementation detail of RB_FL_UNSET().  3rd parties need not use
 * this.  Just always use RB_FL_UNSET().
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` cleared.
 *
 * @internal
 *
 * This  is  function is  here  to  annotate  a  part of  RB_FL_UNSET_RAW()  as
 * `__declspec(noalias)`.
 */
static inline void
rbimpl_fl_unset_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags &= ~flags;
}

RBIMPL_ATTR_ARTIFICIAL()
/**
 * This is an implementation detail of RB_FL_UNSET().  3rd parties need not use
 * this.  Just always use RB_FL_UNSET().
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` cleared.
 */
static inline void
RB_FL_UNSET_RAW(VALUE obj, VALUE flags)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    rbimpl_fl_unset_raw_raw(RBASIC(obj), flags);
}

RBIMPL_ATTR_ARTIFICIAL()
/**
 * Clears the given flag(s).
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` cleard.
 */
static inline void
RB_FL_UNSET(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_UNSET_RAW(obj, flags);
    }
}

RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * @private
 *
 * This is an  implementation detail of RB_FL_REVERSE().  3rd  parties need not
 * use this.  Just always use RB_FL_REVERSE().
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` reversed.
 *
 * @internal
 *
 * This  is function  is  here to  annotate a  part  of RB_FL_REVERSE_RAW()  as
 * `__declspec(noalias)`.
 */
static inline void
rbimpl_fl_reverse_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags ^= flags;
}

RBIMPL_ATTR_ARTIFICIAL()
/**
 * This is an  implementation detail of RB_FL_REVERSE().  3rd  parties need not
 * use this.  Just always use RB_FL_REVERSE().
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` cleared.
 */
static inline void
RB_FL_REVERSE_RAW(VALUE obj, VALUE flags)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    rbimpl_fl_reverse_raw_raw(RBASIC(obj), flags);
}

RBIMPL_ATTR_ARTIFICIAL()
/**
 * Reverses the flags.  This function is here mainly for symmetry on set/unset.
 * Rarely used in practice.
 *
 * @param[out]  obj    Object in question.
 * @param[in]   flags  A set of enum ::ruby_fl_type.
 * @post        `obj` has `flags` reversed.
 */
static inline void
RB_FL_REVERSE(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_REVERSE_RAW(obj, flags);
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_DEPRECATED(("taintedness turned out to be a wrong idea."))
/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @param[in]   obj  Object in question.
 * @return      false always.
 */
static inline bool
RB_OBJ_TAINTABLE(VALUE obj)
{
    (void)obj;
    return false;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_DEPRECATED(("taintedness turned out to be a wrong idea."))
/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @param[in]   obj  Object in question.
 * @return      false always.
 */
static inline VALUE
RB_OBJ_TAINTED_RAW(VALUE obj)
{
    (void)obj;
    return false;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_DEPRECATED(("taintedness turned out to be a wrong idea."))
/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @param[in]   obj  Object in question.
 * @return      false always.
 */
static inline bool
RB_OBJ_TAINTED(VALUE obj)
{
    (void)obj;
    return false;
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_DEPRECATED(("taintedness turned out to be a wrong idea."))
/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @param[in]   obj  Object in question.
 */
static inline void
RB_OBJ_TAINT_RAW(VALUE obj)
{
    (void)obj;
    return;
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_DEPRECATED(("taintedness turned out to be a wrong idea."))
/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @param[in]   obj  Object in question.
 */
static inline void
RB_OBJ_TAINT(VALUE obj)
{
    (void)obj;
    return;
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_DEPRECATED(("taintedness turned out to be a wrong idea."))
/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @param[in]   dst  Victim object.
 * @param[in]   src  Infectant object.
 */
static inline void
RB_OBJ_INFECT_RAW(VALUE dst, VALUE src)
{
    (void)dst;
    (void)src;
    return;
}

RBIMPL_ATTR_ARTIFICIAL()
RBIMPL_ATTR_DEPRECATED(("taintedness turned out to be a wrong idea."))
/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @param[in]   dst  Victim object.
 * @param[in]   src  Infectant object.
 */
static inline void
RB_OBJ_INFECT(VALUE dst, VALUE src)
{
    (void)dst;
    (void)src;
    return;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * This is an  implementation detail of RB_OBJ_FROZEN().  3rd  parties need not
 * use this.  Just always use RB_OBJ_FROZEN().
 *
 * @param[in]  obj             Object in question.
 * @retval     RUBY_FL_FREEZE  Yes it is.
 * @retval     0               No it isn't.
 *
 * @internal
 *
 * It is intentional  not to return bool  here.  There is a place  in ruby core
 * (namely `class.c:singleton_class_of()`) where return  value of this function
 * is passed to RB_FL_SET_RAW().
 */
static inline VALUE
RB_OBJ_FROZEN_RAW(VALUE obj)
{
    return RB_FL_TEST_RAW(obj, RUBY_FL_FREEZE);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks if an object is frozen.
 *
 * @param[in]  obj    Object in question.
 * @retval     true   Yes it is.
 * @retval     false  No it isn't.
 */
static inline bool
RB_OBJ_FROZEN(VALUE obj)
{
    if (! RB_FL_ABLE(obj)) {
        return true;
    }
    else {
        return RB_OBJ_FROZEN_RAW(obj);
    }
}

RBIMPL_ATTR_ARTIFICIAL()
/**
 * This is an  implementation detail of RB_OBJ_FREEZE().  3rd  parties need not
 * use this.  Just always use RB_OBJ_FREEZE().
 *
 * @param[out]  obj  Object in question.
 */
static inline void
RB_OBJ_FREEZE_RAW(VALUE obj)
{
    RB_FL_SET_RAW(obj, RUBY_FL_FREEZE);
}

RUBY_SYMBOL_EXPORT_BEGIN
void rb_obj_freeze_inline(VALUE obj);
RUBY_SYMBOL_EXPORT_END

#endif /* RBIMPL_FL_TYPE_H */
