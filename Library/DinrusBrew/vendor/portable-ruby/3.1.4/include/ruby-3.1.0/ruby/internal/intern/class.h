#ifndef RBIMPL_INTERN_CLASS_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_CLASS_H
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
 * @brief      Public APIs related to ::rb_cClass/::rb_cModule.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/backward/2/stdarg.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* class.c */

/**
 * Creates a new, anonymous class.
 *
 * @param[in]  super          What would become a parent class.
 * @exception  rb_eTypeError  `super` is not something inheritable.
 * @return     An anonymous class that inherits `super`.
 */
VALUE rb_class_new(VALUE super);

/**
 * The comment  that comes with  this function  says `:nodoc:`.  Not  sure what
 * that means though.
 *
 * @param[out]  clone          Destination object.
 * @param[in]   orig           Source object.
 * @exception   rb_eTypeError  Cannot copy `orig`.
 * @return      The passed `clone`.
 */
VALUE rb_mod_init_copy(VALUE clone, VALUE orig);

/**
 * Asserts that  the given class  can derive a child  class.  A class  might or
 * might not be able to do so; for instance a singleton class cannot.
 *
 * @param[in]  super          Possible super class.
 * @exception  rb_eTypeError  No it cannot.
 * @post       Upon successful return `super` can derive.
 */
void rb_check_inheritable(VALUE super);

/**
 * This is a very badly designed API that creates an anonymous class.
 *
 * @param[in]  id             Discarded for no reason (why...).
 * @param[in]  super          What  would  become  a  parent  class.   0  means
 *                            ::rb_cObject.
 * @exception  rb_eTypeError  `super` is not something inheritable.
 * @return     An anonymous class that inherits `super`.
 * @warning    You must explicitly name the return value.
 */
VALUE rb_define_class_id(ID id, VALUE super);

/**
 * Identical  to rb_define_class_under(),  except  it takes  the  name in  ::ID
 * instead of C's string.
 *
 * @param[out]  outer          A class which contains the new class.
 * @param[in]   id             Name of the new class
 * @param[in]   super          A class from which the new class will derive.
 *                             0 means ::rb_cObject.
 * @exception   rb_eTypeError  The constant name `id`  is already taken but the
 *                             constant is not a class.
 * @exception   rb_eTypeError  The class  is already defined but  the class can
 *                             not be  reopened because  its superclass  is not
 *                             `super`.
 * @exception   rb_eArgError   `super` is NULL.
 * @return      The created class.
 * @post        `outer::id` refers the returned class.
 * @note        If a class named `id` is  already defined and its superclass is
 *              `super`, the function just returns the defined class.
 * @note        The  compaction  GC does  not  move  classes returned  by  this
 *              function.
 */
VALUE rb_define_class_id_under(VALUE outer, ID id, VALUE super);

/**
 * Creates a new, anonymous module.
 *
 * @return An anonymous module.
 */
VALUE rb_module_new(void);


/**
 * Creates a new, anonymous refinement.
 *
 * @return An anonymous refinement.
 */
VALUE rb_refinement_new(void);

/**
 * This is a very badly designed API that creates an anonymous module.
 *
 * @param[in]  id  Discarded for no reason (why...).
 * @return     An anonymous module.
 * @warning    You must explicitly name the return value.
 */
VALUE rb_define_module_id(ID id);

/**
 * Identical  to rb_define_module_under(),  except it  takes the  name in  ::ID
 * instead of C's string.
 *
 * @param[out]  outer          A class which contains the new module.
 * @param[in]   id             Name of the new module
 * @exception   rb_eTypeError  The constant name `id`  is already taken but the
 *                             constant is not a module.
 * @return      The created module.
 * @post        `outer::id` refers the returned module.
 * @note        The  compaction  GC does  not  move  classes returned  by  this
 *              function.
 */
VALUE rb_define_module_id_under(VALUE outer, ID id);

/**
 * Queries the list of  included modules.  It can also be seen  as a routine to
 * first  call rb_mod_ancestors(),  then  rejects non-modules  from the  return
 * value.
 *
 * @param[in]  mod  Class or Module.
 * @return     An array of modules that are either included or prepended in any
 *             of `mod`'s ancestry tree (including itself).
 */
VALUE rb_mod_included_modules(VALUE mod);

/**
 * Queries if the passed module is included by the module.  It can also be seen
 * as a routine to first call rb_mod_included_modules(), then see if the return
 * value contains the passed module.
 *
 * @param[in]  child          A Module.
 * @param[in]  parent         Another Module.
 * @exception  rb_eTypeError  `child` is not an instance of ::rb_cModule.
 * @retval     RUBY_Qtrue     `parent` is  either included or prepended  in any
 *                            of `child`'s ancestry tree (including itself).
 * @return     RUBY_Qfalse    Otherwise.
 */
VALUE rb_mod_include_p(VALUE child, VALUE parent);

/**
 * Queries the  module's ancestors.  This routine gathers classes  and modules
 * that  the  passed  module  either  inherits,  includes,  or  prepends,  then
 * recursively applies  that routine again  and again to the  collected entries
 * until the list doesn't grow up.
 *
 * @param[in]  mod  A module or a class.
 * @return     An array of  classes or modules that  `mod` possibly recursively
 *             inherits, includes, or prepends.
 *
 * @internal
 *
 * Above description  is written  in a  recursive language  but in  practice it
 * computes the return value iteratively.
 */
VALUE rb_mod_ancestors(VALUE mod);

/**
 * Queries the class's descendants. This  routine gathers classes that are
 * subclasses of the given class (or subclasses of those subclasses, etc.),
 * returning an array of classes that have the given class as an ancestor.
 * The returned array does not include the given class or singleton classes.
 *
 * @param[in]  klass A class.
 * @return     An array of classes where `klass` is an ancestor.
 *
 * @internal
 */
VALUE rb_class_descendants(VALUE klass);

/**
 * Queries the class's direct descendants. This  routine gathers classes that are
 * direct subclasses of the given class,
 * returning an array of classes that have the given class as a superclass.
 * The returned array does not include singleton classes.
 *
 * @param[in]  klass A class.
 * @return     An array of classes where `klass` is the `superclass`.
 *
 * @internal
 */
VALUE rb_class_subclasses(VALUE klass);

/**
 * Generates an array of symbols, which are the list of method names defined in
 * the passed class.
 *
 * @param[in]  argc          Number of objects of `argv`.
 * @param[in]  argv          Array of  at most  one object, which  controls (if
 *                           any) whether  the return array includes  the names
 *                           of methods defined in ancestors or not.
 * @param[in]  mod           A module or a class.
 * @exception  rb_eArgError  `argc` out of range.
 * @return     An array  of symbols collecting  names of instance  methods that
 *             are not private, defined at `mod`.
 */
VALUE rb_class_instance_methods(int argc, const VALUE *argv, VALUE mod);

/**
 * Identical to rb_class_instance_methods(), except it returns names of methods
 * that are public only.
 *
 * @param[in]  argc          Number of objects of `argv`.
 * @param[in]  argv          Array of  at most  one object, which  controls (if
 *                           any) whether  the return array includes  the names
 *                           of methods defined in ancestors or not.
 * @param[in]  mod           A module or a class.
 * @exception  rb_eArgError  `argc` out of range.
 * @return     An array  of symbols collecting  names of instance  methods that
 *             are public, defined at `mod`.
 */
VALUE rb_class_public_instance_methods(int argc, const VALUE *argv, VALUE mod);

/**
 * Identical to rb_class_instance_methods(), except it returns names of methods
 * that are protected only.
 *
 * @param[in]  argc          Number of objects of `argv`.
 * @param[in]  argv          Array of  at most  one object, which  controls (if
 *                           any) whether  the return array includes  the names
 *                           of methods defined in ancestors or not.
 * @param[in]  mod           A module or a class.
 * @exception  rb_eArgError  `argc` out of range.
 * @return     An array  of symbols collecting  names of instance  methods that
 *             are protected, defined at `mod`.
 */
VALUE rb_class_protected_instance_methods(int argc, const VALUE *argv, VALUE mod);

/**
 * Identical to rb_class_instance_methods(), except it returns names of methods
 * that are private only.
 *
 * @param[in]  argc          Number of objects of `argv`.
 * @param[in]  argv          Array of  at most  one object, which  controls (if
 *                           any) whether  the return array includes  the names
 *                           of methods defined in ancestors or not.
 * @param[in]  mod           A module or a class.
 * @exception  rb_eArgError  `argc` out of range.
 * @return     An array  of symbols collecting  names of instance  methods that
 *             are protected, defined at `mod`.
 */
VALUE rb_class_private_instance_methods(int argc, const VALUE *argv, VALUE mod);

/**
 * Identical  to  rb_class_instance_methods(),  except   it  returns  names  of
 * singleton methods instead of instance methods.
 *
 * @param[in]  argc          Number of objects of `argv`.
 * @param[in]  argv          Array of  at most  one object, which  controls (if
 *                           any) whether  the return array includes  the names
 *                           of methods defined in ancestors or not.
 * @param[in]  obj           Arbitrary ruby object.
 * @exception  rb_eArgError  `argc` out of range.
 * @return     An array  of symbols collecting  names of instance  methods that
 *             are not private, defined at the singleton class of `obj`.
 */
VALUE rb_obj_singleton_methods(int argc, const VALUE *argv, VALUE obj);

/**
 * Identical to rb_define_method(),  except it takes the name of  the method in
 * ::ID instead of C's string.
 *
 * @param[out]  klass  A module or a class.
 * @param[in]   mid    Name of the function.
 * @param[in]   func   The method body.
 * @param[in]   arity  The number of parameters.  See @ref defmethod.
 * @note        There are in fact 18 different prototypes for func.
 * @see         ::ruby::backward::cxxanyargs::define_method::rb_define_method_id
 */
void rb_define_method_id(VALUE klass, ID mid, VALUE (*func)(ANYARGS), int arity);

/* vm_method.c */

/**
 * Inserts a  method entry that hides  previous method definition of  the given
 * name.  This is not a deletion of  a method.  Method of the same name defined
 * in a parent class is kept invisible in this way.
 *
 * @param[out]  mod              The module to insert an undef.
 * @param[in]   mid              Name of the undef.
 * @exception   rb_eTypeError    `klass` is a non-module.
 * @exception   rb_eFrozenError  `klass` is frozen.
 * @exception   rb_eNameError    No such method named `klass#name`.
 * @post        `klass#name` is undefined.
 * @see         rb_undef_method
 *
 * @internal
 *
 * @shyouhei doesn't  understand why this  is not  the ::ID -taking  variant of
 * rb_undef_method(), given rb_remove_method() has its ::ID -taking counterpart
 * named rb_remove_method_id().
 */
void rb_undef(VALUE mod, ID mid);

/* class.c */

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_define_method(), except it defines a protected method.
 *
 * @param[out]  klass  A module or a class.
 * @param[in]   mid    Name of the function.
 * @param[in]   func   The method body.
 * @param[in]   arity  The number of parameters.  See @ref defmethod.
 * @note        There are in fact 18 different prototypes for func.
 * @see         ::ruby::backward::cxxanyargs::define_method::rb_define_protected_method
 */
void rb_define_protected_method(VALUE klass, const char *mid, VALUE (*func)(ANYARGS), int arity);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_define_method(), except it defines a private method.
 *
 * @param[out]  klass  A module or a class.
 * @param[in]   mid    Name of the function.
 * @param[in]   func   The method body.
 * @param[in]   arity  The number of parameters.  See @ref defmethod.
 * @note        There are in fact 18 different prototypes for func.
 * @see         ::ruby::backward::cxxanyargs::define_method::rb_define_protected_method
 */
void rb_define_private_method(VALUE klass, const char *mid, VALUE (*func)(ANYARGS), int arity);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_define_method(), except it defines a singleton method.
 *
 * @param[out]  obj    Arbitrary ruby object.
 * @param[in]   mid    Name of the function.
 * @param[in]   func   The method body.
 * @param[in]   arity  The number of parameters.  See @ref defmethod.
 * @note        There are in fact 18 different prototypes for func.
 * @see         ::ruby::backward::cxxanyargs::define_method::rb_define_singleton_method
 */
void rb_define_singleton_method(VALUE obj, const char *mid, VALUE(*func)(ANYARGS), int arity);

/**
 * Finds or creates the singleton class of the passed object.
 *
 * @param[out]  obj            Arbitrary ruby object.
 * @exception   rb_eTypeError  `obj` cannot have its singleton class.
 * @return      A (possibly newly allocated) instance of ::rb_cClass.
 * @post        `obj` has its singleton class, which is the return value.
 * @post        In case `obj` is a class, the returned singleton class also has
 *              its own  singleton class  in order to  keep consistency  of the
 *              inheritance structure of metaclasses.
 * @note        A new  singleton class will  be created  if `obj` did  not have
 *              one.
 * @note        The  singleton  classes   for  ::RUBY_Qnil,  ::RUBY_Qtrue,  and
 *              ::RUBY_Qfalse   are    ::rb_cNilClass,   ::rb_cTrueClass,   and
 *              ::rb_cFalseClass respectively.
 *
 * @internal
 *
 * You can _create_ a singleton class of a frozen object.  Intentional or ...?
 *
 * Nowadays there are wider range of  objects who cannot have singleton classes
 * than before.  For instance some string instances cannot for some reason.
 */
VALUE rb_singleton_class(VALUE obj);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_CLASS_H */
