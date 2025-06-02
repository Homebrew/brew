#ifndef RBIMPL_NEWOBJ_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_NEWOBJ_H
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
 * @brief      Defines #NEWOBJ.
 */
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/value.h"
#include "ruby/assert.h"

/**
 * Declares, allocates, then assigns a new object to the given variable.
 *
 * @param      obj             Variable name.
 * @param      type            Variable type.
 * @exception  rb_eNoMemError  No space left.
 * @return     An allocated object, not initialised.
 * @note       Modern programs tend to use #NEWOBJ_OF instead.
 *
 * @internal
 *
 * :FIXME: Should we deprecate it?
 */
#define RB_NEWOBJ(obj,type) type *(obj) = RBIMPL_CAST((type *)rb_newobj())

/**
 * Identical  to #RB_NEWOBJ,  except it  also accepts  the allocating  object's
 * class and flags.
 *
 * @param      obj             Variable name.
 * @param      type            Variable type.
 * @param      klass           Object's class.
 * @param      flags           Object's flags.
 * @exception  rb_eNoMemError  No space left.
 * @return     An allocated object, filled with the arguments.
 */
#define RB_NEWOBJ_OF(obj,type,klass,flags) type *(obj) = RBIMPL_CAST((type *)rb_newobj_of(klass, flags))

#define NEWOBJ     RB_NEWOBJ      /**< @old{RB_NEWOBJ} */
#define NEWOBJ_OF  RB_NEWOBJ_OF   /**< @old{RB_NEWOBJ_OF} */
#define OBJSETUP   rb_obj_setup   /**< @old{rb_obj_setup} */
#define CLONESETUP rb_clone_setup /**< @old{rb_clone_setup} */
#define DUPSETUP   rb_dup_setup   /**< @old{rb_dup_setup} */

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * This is the implementation detail of #RB_NEWOBJ.
 *
 * @exception  rb_eNoMemError  No space left.
 * @return     An allocated object, not initialised.
 */
VALUE rb_newobj(void);

/**
 * This is the implementation detail of #RB_NEWOBJ_OF.
 *
 * @param      klass           Object's class.
 * @param      flags           Object's flags.
 * @exception  rb_eNoMemError  No space left.
 * @return     An allocated object, filled with the arguments.
 */
VALUE rb_newobj_of(VALUE klass, VALUE flags);

/**
 * Fills common fields in the object.
 *
 * @note           Prefer rb_newobj_of() to this function.
 * @param[in,out]  obj    A Ruby object to be set up.
 * @param[in]      klass  `obj` will belong to this class.
 * @param[in]      type   One of ::ruby_value_type.
 * @return         The passed object.
 *
 * @internal
 *
 * Historically, authors of  Ruby has described the `type` argument  as "one of
 * ::ruby_value_type".   In   reality  it  accepts   either  ::ruby_value_type,
 * ::ruby_fl_type,   or   any   combinations   of  the   two.    For   instance
 * `RUBY_T_STRING | RUBY_FL_FREEZE` is a valid  value that this function takes,
 * and means this is a frozen string.
 *
 * 3rd  party extension  libraries rarely  need to  allocate Strings  this way.
 * They normally only concern ::RUBY_T_DATA.   This argument is mainly used for
 * specifying flags, @shyouhei suspects.
 */
VALUE rb_obj_setup(VALUE obj, VALUE klass, VALUE type);

/**
 * Queries  the  class  of  an  object.    This  is  not  always  identical  to
 * `RBASIC_CLASS(obj)`.   It   searches  for  the  nearest   ancestor  skipping
 * singleton classes or included modules.
 *
 * @param[in]  obj  Object in question.
 * @return     The object's class, in a normal sense.
 */
VALUE rb_obj_class(VALUE obj);

/**
 * Clones a singleton class.  An object  can have its own singleton class.  OK.
 * Then what  happens when a program  clones such object?  The  singleton class
 * that is  attached to  the source  object must also  be cloned.   Otherwise a
 * singleton object gets shared with two objects, which breaks "singleton"-ness
 * of such class.
 *
 * This  is basically  an  implementation detail  of rb_clone_setup().   People
 * need not be aware of this working behind-the-scene.
 *
 * @param[in]  obj  The object that has its own singleton class.
 * @return     Cloned singleton class.
 */
VALUE rb_singleton_class_clone(VALUE obj);

/**
 * Attaches a singleton class to its corresponding object.
 *
 * This  is basically  an  implementation detail  of rb_clone_setup().   People
 * need not be aware of this working behind-the-scene.
 *
 * @param[in]   klass  The singleton class.
 * @param[out]  obj    The object to attach a class.
 * @pre         The passed two objects must  agree with each other that `klass`
 *              becomes a singleton class of `obj`.
 * @post        `klass` becomes the singleton class of `obj`.
 */
void rb_singleton_class_attached(VALUE klass, VALUE obj);

/**
 * Copies the list of instance variables.  3rd parties need not know, but there
 * are several ways  to store an object's instance variables,  depending on its
 * internal structure.   This function  makes sense when  either of  the passed
 * objects are using so-called "generic"  backend storage.  This distinction is
 * purely an  implementation detail  of rb_clone_setup().   People need  not be
 * aware of this working behind-the-scenes.
 *
 * @param[out]  clone  The destination object.
 * @param[in]   obj    The source object.
 */
void rb_copy_generic_ivar(VALUE clone, VALUE obj);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_DEPRECATED(("This is no longer how Object#clone works."))
/**
 * @deprecated  Not sure exactly  when but at some time,  the implementation of
 *              `Object#clone`  stopped  using   this  function.   It  remained
 *              untouched for  a while, and  then @shyouhei realised  that they
 *              are no longer doing the  same thing.  It seems nobody seriously
 *              uses this function any longer.  Let's just abandon it.
 *
 * @param[out]  clone  The destination object.
 * @param[in]   obj    The source object.
 */
static inline void
rb_clone_setup(VALUE clone, VALUE obj)
{
    (void)clone;
    (void)obj;
    return;
}

RBIMPL_ATTR_DEPRECATED(("This is no longer how Object#dup works."))
/**
 * @deprecated  Not sure exactly  when but at some time,  the implementation of
 *              `Object#dup`   stopped  using   this  function.    It  remained
 *              untouched for  a while, and  then @shyouhei realised  that they
 *              are no longer  the same thing.  It seems  nobody seriously uses
 *              this function any longer.  Let's just abandon it.
 *
 * @param[out]  dup  The destination object.
 * @param[in]   obj  The source object.
 */
static inline void
rb_dup_setup(VALUE dup, VALUE obj)
{
    (void)dup;
    (void)obj;
    return;
}

#endif /* RBIMPL_NEWOBJ_H */
