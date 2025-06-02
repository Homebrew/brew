#ifndef RBIMPL_ROBJECT_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ROBJECT_H
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
 * @brief      Defines struct ::RObject.
 */
#include "ruby/internal/config.h"

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"

/**
 * Convenient casting macro.
 *
 * @param   obj  An object, which is in fact an ::RRegexp.
 * @return  The passed object casted to ::RRegexp.
 */
#define ROBJECT(obj)          RBIMPL_CAST((struct RObject *)(obj))
/** @cond INTERNAL_MACRO */
#define ROBJECT_EMBED_LEN_MAX ROBJECT_EMBED_LEN_MAX
#define ROBJECT_EMBED         ROBJECT_EMBED
#define ROBJECT_NUMIV         ROBJECT_NUMIV
#define ROBJECT_IVPTR         ROBJECT_IVPTR
#define ROBJECT_IV_INDEX_TBL  ROBJECT_IV_INDEX_TBL
/** @endcond */

/**
 * @private
 *
 * Bits that you can set to ::RBasic::flags.
 */
enum ruby_robject_flags {
    /**
     * This flag has  something to do with memory footprint.   If the object is
     * "small"  enough, ruby  tries to  be creative  to abuse  padding bits  of
     * struct ::RObject for storing instance variables.  This flag denotes that
     * situation.
     *
     * @warning  This  bit has  to be  considered read-only.   Setting/clearing
     *           this  bit without  corresponding fix  up must  cause immediate
     *           SEGV.   Also,   internal  structures   of  an   object  change
     *           dynamically  and  transparently  throughout of  its  lifetime.
     *           Don't assume it being persistent.
     *
     * @internal
     *
     * 3rd parties must  not be aware that  there even is more than  one way to
     * store instance variables.  Might better be hidden.
     */
    ROBJECT_EMBED = RUBY_FL_USER1
};

/**
 * This is an enum because GDB wants it (rather than a macro).  People need not
 * bother.
 */
enum ruby_robject_consts {
    /** Max possible number of instance variables that can be embedded. */
    ROBJECT_EMBED_LEN_MAX = RBIMPL_EMBED_LEN_MAX_OF(VALUE)
};

struct st_table;

/**
 * Ruby's ordinal objects.  Unless otherwise  special cased, all predefined and
 * user-defined classes share this struct to hold their instances.
 */
struct RObject {

    /** Basic part, including flags and class. */
    struct RBasic basic;

    /** Object's specific fields. */
    union {

        /**
         * Object that use  separated memory region for  instance variables use
         * this pattern.
         */
        struct {

            /**
             * Number of instance variables.  This is per object; objects might
             * differ in this field even if they have the identical classes.
             */
            uint32_t numiv;

            /** Pointer to a C array that holds instance variables. */
            VALUE *ivptr;

            /**
             * This  is a  table that  holds  instance variable  name to  index
             * mapping.  Used when accessing instance variables using names.
             *
             * @internal
             *
             * This is a shortcut for `RCLASS_IV_INDEX_TBL(rb_obj_class(obj))`.
             */
            struct st_table *iv_index_tbl;
        } heap;

        /**
         * Embedded instance  variables.  When  an object  is small  enough, it
         * uses this area to store the instance variables.
         */
        VALUE ary[ROBJECT_EMBED_LEN_MAX];
    } as;
};

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries the number of instance variables.
 *
 * @param[in]  obj  Object in question.
 * @return     Its number of instance variables.
 * @pre        `obj` must be an instance of ::RObject.
 */
static inline uint32_t
ROBJECT_NUMIV(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        return ROBJECT_EMBED_LEN_MAX;
    }
    else {
        return ROBJECT(obj)->as.heap.numiv;
    }
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries the instance variables.
 *
 * @param[in]  obj  Object in question.
 * @return     Its instance variables, in C array.
 * @pre        `obj` must be an instance of ::RObject.
 *
 * @internal
 *
 * @shyouhei finds no reason for this to be visible from extension libraries.
 */
static inline VALUE *
ROBJECT_IVPTR(VALUE obj)
{
    RBIMPL_ASSERT_TYPE(obj, RUBY_T_OBJECT);

    struct RObject *const ptr = ROBJECT(obj);

    if (RB_FL_ANY_RAW(obj, ROBJECT_EMBED)) {
        return ptr->as.ary;
    }
    else {
        return ptr->as.heap.ivptr;
    }
}

#endif /* RBIMPL_ROBJECT_H */
