#ifndef RBIMPL_RCLASS_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RCLASS_H
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
 * @brief      Routines to manipulate struct RClass.
 * @note       The struct RClass itself is opaque.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/cast.h"

/** @cond INTERNAL_MACRO */
#define RMODULE_IS_REFINEMENT            RMODULE_IS_REFINEMENT
/** @endcond */

/**
 * Convenient casting macro.
 *
 * @param   obj  An object, which is in fact an RClass.
 * @return  The passed object casted to RClass.
 */
#define RCLASS(obj)  RBIMPL_CAST((struct RClass *)(obj))

/** @alias{RCLASS} */
#define RMODULE      RCLASS

/** @alias{rb_class_get_superclass} */
#define RCLASS_SUPER rb_class_get_superclass

/**
 * @private
 *
 * Bits that you can set to ::RBasic::flags.
 *
 * @internal
 *
 * Why is it here, given RClass itself is not?
 */
enum ruby_rmodule_flags {
    /**
     * This flag has something to do  with refinements.  A module created using
     * rb_mod_refine()  has this  flag set.   This  is the  bit which  controls
     * difference between normal inclusion versus refinements.
     */
    RMODULE_IS_REFINEMENT            = RUBY_FL_USER3
};

struct RClass; /* Opaque, declared here for RCLASS() macro. */

RBIMPL_SYMBOL_EXPORT_BEGIN()
/**
 * Returns the superclass of a class.
 * @param[in]  klass        An object of RClass.
 * @retval     RUBY_Qfalse  `klass` has no super class.
 * @retval     otherwise    Raw superclass of `klass`
 * @see        rb_class_superclass
 *
 * ### Q&A ###
 *
 * - Q: How can a class have no super class?
 *
 * - A: `klass` could be a module.  Or it could be ::rb_cBasicObject.
 *
 * - Q: What do you mean by "raw" superclass?
 *
 * - A: This  is a  really good  question.  The  answer is  that this  function
 *      returns something  different from what  you would normally  expect.  On
 *      occasions  ruby  inserts  hidden  classes   in  a  hierarchy  of  class
 *      inheritance behind-the-scene.   Such classes are called  "iclass"es and
 *      distinguished  using  ::RUBY_T_ICLASS  in  C  level.   They  are  truly
 *      transparent from Ruby  level but can be accessed from  C, by using this
 *      API.
 */
VALUE rb_class_get_superclass(VALUE klass);
RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_RCLASS_H */
