#ifndef RBIMPL_RBASIC_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RBASIC_H
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
 * @brief      Defines struct ::RBasic.
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/attr/forceinline.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/value.h"
#include "ruby/assert.h"

/**
 * Convenient casting macro.
 *
 * @param   obj  Arbitrary Ruby object.
 * @return  The passed object casted to ::RBasic.
 */
#define RBASIC(obj)                 RBIMPL_CAST((struct RBasic *)(obj))
/** @cond INTERNAL_MACRO */
#define RBASIC_CLASS                RBASIC_CLASS
#define RBIMPL_RVALUE_EMBED_LEN_MAX 3
#define RVALUE_EMBED_LEN_MAX        RVALUE_EMBED_LEN_MAX
#define RBIMPL_EMBED_LEN_MAX_OF(T) \
    RBIMPL_CAST((int)(sizeof(VALUE[RBIMPL_RVALUE_EMBED_LEN_MAX]) / (sizeof(T))))
/** @endcond */

/**
 * This is an enum because GDB wants it (rather than a macro).  People need not
 * bother.
 */
enum ruby_rvalue_flags {
    /** Max possible number of objects that can be embedded. */
    RVALUE_EMBED_LEN_MAX = RBIMPL_RVALUE_EMBED_LEN_MAX
};

/**
 * Ruby's object's,  base components.  Every  single ruby objects have  them in
 * common.
 */
struct
RUBY_ALIGNAS(SIZEOF_VALUE)
RBasic {

    /**
     * Per-object  flags.  Each  ruby  objects have  their own  characteristics
     * apart from their  classes.  For instance whether an object  is frozen or
     * not is not  controlled by its class.  This is  where such properties are
     * stored.
     *
     * @see enum ::ruby_fl_type
     *
     * @note  This is ::VALUE rather than  an enum for alignment purpose.  Back
     *        in the 1990s there were no such thing like `_Alignas` in C.
     */
    VALUE flags;

    /**
     * Class of an object.  Every object has its class.  Also, everything is an
     * object  in Ruby.   This means  classes are  also objects.   Classes have
     * their own classes,  classes of classes have their classes,  too ...  and
     * it recursively continues forever.
     *
     * Also note the `const` qualifier.  In  ruby an object cannot "change" its
     * class.
     */
    const VALUE klass;

#ifdef __cplusplus
  public:
    RBIMPL_ATTR_CONSTEXPR(CXX11)
    RBIMPL_ATTR_ARTIFICIAL()
    RBIMPL_ATTR_FORCEINLINE()
    RBIMPL_ATTR_NOALIAS()
    /**
     * We need to define this explicit constructor because the field `klass` is
     * const-qualified above,  which effectively  defines the  implicit default
     * constructor as "deleted"  (as of C++11) --  No way but to  define one by
     * ourselves.
     */
    RBasic() :
        flags(RBIMPL_VALUE_NULL),
        klass(RBIMPL_VALUE_NULL)
    {
    }
#endif
};

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * Make the object invisible from Ruby code.
 *
 * It is  useful to let  Ruby's GC manage your  internal data structure  -- The
 * object keeps being managed by GC, but `ObjectSpace.each_object` never yields
 * the object.
 *
 * Note that the object also lose a way to call a method on it.
 *
 * @param[out]  obj  A Ruby object.
 * @return      The passed object.
 * @post        The object is destructively modified to be invisible.
 * @see         rb_obj_reveal
 */
VALUE rb_obj_hide(VALUE obj);

/**
 * Make a hidden object visible again.
 *
 * It is  the caller's  responsibility to  pass the  right `klass`  which `obj`
 * originally used to belong to.
 *
 * @param[out]  obj    A Ruby object.
 * @param[in]   klass  Class of `obj`.
 * @return      Passed `obj`.
 * @pre         `obj` was previously hidden.
 * @post        `obj`'s class is `klass`.
 * @see         rb_obj_hide
 */
VALUE rb_obj_reveal(VALUE obj, VALUE klass); /* do not use this API to change klass information */
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Queries the class of an object.
 *
 * @param[in]  obj  An object.
 * @return     Its class.
 */
static inline VALUE
RBASIC_CLASS(VALUE obj)
{
    RBIMPL_ASSERT_OR_ASSUME(! RB_SPECIAL_CONST_P(obj));
    return RBASIC(obj)->klass;
}

#endif /* RBIMPL_RBASIC_H */
