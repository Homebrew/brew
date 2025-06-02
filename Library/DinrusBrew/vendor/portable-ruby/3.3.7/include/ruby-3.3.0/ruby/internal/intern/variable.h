#ifndef RBIMPL_INTERN_VARIABLE_H                     /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_VARIABLE_H
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
 * @brief      Public APIs related to names inside of a Ruby program.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/st.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* variable.c */

/**
 * Queries the name of a module.
 *
 * @param[in]  mod        An instance of ::rb_cModule.
 * @retval     RUBY_Qnil  `mod` is anonymous.
 * @retval     otherwise  `mod` is onymous.
 */
VALUE rb_mod_name(VALUE mod);

/**
 * Identical  to  rb_mod_name(),  except   it  returns  `#<Class:  ...>`  style
 * inspection for anonymous modules.
 *
 * @param[in]  mod        An instance of ::rb_cModule.
 * @return     An instance of ::rb_cString representing `mod`'s path.
 */
VALUE rb_class_path(VALUE mod);

/**
 * @alias{rb_mod_name}
 *
 * @internal
 *
 * Am I missing something?  Why we have the same thing in different names?
 */
VALUE rb_class_path_cached(VALUE mod);

RBIMPL_ATTR_NONNULL(())
/**
 * Names a class.
 *
 * @param[out]  klass  Target module to name.
 * @param[out]  space  Namespace that `klass` shall reside.
 * @param[in]   name   Name of `klass`.
 * @post        `klass` has `space::klass` name.
 */
void rb_set_class_path(VALUE klass, VALUE space, const char *name);

/**
 * Identical  to rb_set_class_path(),  except  it accepts  the  name as  Ruby's
 * string instead of C's.
 *
 * @param[out]  klass  Target module to name.
 * @param[out]  space  Namespace that `klass` shall reside.
 * @param[in]   name   Name of `klass`.
 * @post        `klass` has `space::klass` name.
 */
void rb_set_class_path_string(VALUE klass, VALUE space, VALUE name);

/**
 * Identical to  rb_path2class(), except it  accepts the path as  Ruby's string
 * instead of C's.
 *
 * @param[in]  path           Path to query.
 * @exception  rb_eArgError   No such constant.
 * @exception  rb_eTypeError  The path resolved to a non-module.
 * @return     Resolved class.
 */
VALUE rb_path_to_class(VALUE path);

RBIMPL_ATTR_NONNULL(())
/**
 * Resolves a `Q::W::E::R`-style path string to the actual class it points.
 *
 * @param[in]  path           Path to query.
 * @exception  rb_eArgError   No such constant.
 * @exception  rb_eTypeError  The path resolved to a non-module.
 * @return     Resolved class.
 */
VALUE rb_path2class(const char *path);

/**
 * Queries the name of the given object's class.
 *
 * @param[in]  obj  Arbitrary object.
 * @return     An instance of ::rb_cString representing `obj`'s class' path.
 */
VALUE rb_class_name(VALUE obj);

/**
 * Kicks the autoload procedure as if it was "touched".
 *
 * @param[out]  space        Namespace where autoload is defined.
 * @param[in]   name         Name of the autoloaded constant.
 * @retval      RUBY_Qfalse  No such autoload.
 * @retval      RUBY_Qtrue   Autoload successfully initiated.
 * @note        As an  autoloaded library is expected  to define `space::name`,
 *              it is  a nature  of this function  to have  process-global side
 *              effects.
 * @note        Multiple threads  can simultaneously call this  API.  It blocks
 *              then.  That must not last indefinitely but can take longer than
 *              you expect.
 *
 * @internal
 *
 * @shyouhei has no idea why extension libraries should use this API.
 */
VALUE rb_autoload_load(VALUE space, ID name);

/**
 * Queries if an autoload is defined at a point.
 *
 * @param[in]  space      Namespace where autoload is defined.
 * @param[in]  name       Name of the autoloaded constant.
 * @retval     RUBY_Qnil  No such autoload.
 * @retval     otherwise  The feature (path) registered at `space::name`.
 */
VALUE rb_autoload_p(VALUE space, ID name);

/**
 * Traces a global variable.
 *
 * @param[in]  argc        Either 1 or 2.
 * @param[in]  argv        Variable name, optionally a Proc.
 * @retval     RUBY_Qnil   No previous tracers.
 * @retval     otherwise   Previous tracers.
 *
 * @internal
 *
 * @shyouhei has no idea why extension libraries should use this API.
 */
VALUE rb_f_trace_var(int argc, const VALUE *argv);

/**
 * Deletes the  passed tracer from the  passed global variable, or  if omitted,
 * deletes everything.
 *
 * @param[in]  argc        Either 1 or 2.
 * @param[in]  argv        Variable name, optionally a Proc.
 * @retval     RUBY_Qnil   No previous tracers.
 * @retval     otherwise   Deleted tracers.
 *
 * @internal
 *
 * @shyouhei has no idea why extension libraries should use this API.
 */
VALUE rb_f_untrace_var(int argc, const VALUE *argv);

/**
 * Queries the list of global variables.
 *
 * @return  The list of the name of the global variables.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
VALUE rb_f_global_variables(void);

/**
 * Aliases  a global  variable.   Did you  know  that you  can  alias a  global
 * variable?  It is like aliasing methods:
 *
 * ```ruby
 * alias $dst $src
 * ```
 *
 * This C function does the same thing.
 *
 * @param[in]  dst  Destination name.
 * @param[in]  src  Source name.
 * @post       A global  variable named `dst`  is defined to  be an alias  of a
 *             global variable named `src`.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
void rb_alias_variable(ID dst, ID src);

/**
 * Frees the list of instance variables.   3rd parties need not know, but there
 * are several ways  to store an object's instance variables,  depending on its
 * internal structure.   This function makes  sense when the passed  objects is
 * using so-called "generic" backend storage.  People need not be aware of this
 * working behind-the-scenes.
 *
 * @param[out]  obj  The object in question.
 *
 * @internal
 *
 * This just  destroys the given object.   @shyouhei has no idea  why extension
 * libraries should use this API.
 */
void rb_free_generic_ivar(VALUE obj);

/**
 * Identical to rb_iv_get(), except it accepts the name as an ::ID instead of a
 * C string.
 *
 * @param[in]  obj        Target object.
 * @param[in]  name       Target instance variable to query.
 * @retval     RUBY_nil   No such instance variable.
 * @retval     otherwise  The value assigned to the instance variable.
 */
VALUE rb_ivar_get(VALUE obj, ID name);

/**
 * Identical to rb_iv_set(), except it accepts the name as an ::ID instead of a
 * C string.
 *
 * @param[out]  obj              Target object.
 * @param[in]   name             Target instance variable.
 * @param[in]   val              Value to assign.
 * @exception   rb_eFrozenError  Can't modify `obj`.
 * @exception   rb_eArgError     `obj` has too many instance variables.
 * @return      Passed value.
 * @post        An  instance variable  named  `name` is  defined  if absent  on
 *              `obj`, whose value is set to `val`.
 */
VALUE rb_ivar_set(VALUE obj, ID name, VALUE val);

/**
 * Queries if  the instance variable  is defined  at the object.   This roughly
 * resembles `defined?(@name)` in `obj`'s context.
 *
 * @param[in]  obj          Target object.
 * @param[in]  name         Target instance variable to query.
 * @retval     RUBY_Qtrue   There is an instance variable.
 * @retval     RUBY_Qfalse  No such instance variable.
 */
VALUE rb_ivar_defined(VALUE obj, ID name);

/**
 * Iterates over an object's instance variables.
 *
 * @param[in]  obj   Target object.
 * @param[in]  func  Callback function.
 * @param[in]  arg   Passed as-is to the last argument of `func`.
 */
void rb_ivar_foreach(VALUE obj, int (*func)(ID name, VALUE val, st_data_t arg), st_data_t arg);

/**
 * Number of instance variables defined on an object.
 *
 * @param[in]  obj   Target object.
 * @return     Number of instance variables defined on `obj`.
 */
st_index_t rb_ivar_count(VALUE obj);

/**
 * Identical to rb_ivar_get()
 *
 * @param[in]  obj        Target object.
 * @param[in]  name       Target instance variable to query.
 * @retval     RUBY_nil   No such instance variable.
 * @retval     otherwise  The value assigned to the instance variable.
 *
 * @internal
 *
 * Am I missing something?  Why we have the same thing in different names?
 */
VALUE rb_attr_get(VALUE obj, ID name);

/**
 * Resembles `Object#instance_variables`.
 *
 * @param[in]  obj  Target object to query.
 * @return     An array of instance variable names for the receiver.
 * @note       Simply defining  an accessor  does not create  the corresponding
 *             instance variable.
 */
VALUE rb_obj_instance_variables(VALUE obj);

/**
 * Resembles `Object#remove_instance_variable`.
 *
 * @param[out]  obj   Target object.
 * @param[in]   name  Variable name to remove, either in Symbol or String.
 * @return      What was removed.
 * @pre         Instance variable named `name` is deleted from `obj`.
 */
VALUE rb_obj_remove_instance_variable(VALUE obj, VALUE name);

/**
 * This API is  mysterious.  It has been there since  the initial revision.  No
 * single bits of  documents has ever been written.  The  function name doesn't
 * describe anything.  What should be passed to the argument, or what should be
 * the  return value,  are not  obvious.  Yet  it has  evolved over  time.  The
 * source code is written in counter-intuitive way (as of 3.0).
 *
 * Simply put, don't try to understand this API.
 */
void *rb_mod_const_at(VALUE, void*);

/**
 * This is a variant of rb_mod_const_at().  As a result, it is also mysterious.
 * It _seems_ it iterates over the ancestry  tree of the module.  But what that
 * means is beyond a human brain.
 */
void *rb_mod_const_of(VALUE, void*);

/**
 * This is  another mysterious  API that  comes with no  documents at  all.  It
 * seems it expects  some specific data structure for the  passed pointer.  But
 * the details has  never been made explicit.  It seems  nobody should use this
 * API.
 */
VALUE rb_const_list(void*);

/**
 * Resembles  `Module#constants`.   List  up   the  constants  defined  at  the
 * receiver.  This  includes the  names of constants  in any  included modules,
 * unless `argv[0]` is ::RUBY_Qfalse.
 *
 * The  implementation  makes  no  guarantees  about the  order  in  which  the
 * constants are yielded.
 *
 * @param[in]  argc  Either 0 or 1.
 * @param[in]  argv  Pointer to ::RUBY_Qfalse, if `argc == 1`.
 * @param[in]  recv  Target namespace.
 * @return     An array of symbols, which are constant names under `recv`.
 */
VALUE rb_mod_constants(int argc, const VALUE *argv, VALUE recv);

/**
 * Resembles `Module#remove_const`.
 *
 * @param[out]  space  Target namespace.
 * @param[in]   name   Variable name to remove, either in Symbol or String.
 * @return      What was removed.
 * @pre         Constant named `space::name` is deleted.
 * @note        In case what was removed was in  fact a module or a class, this
 *              operation does  not affect its  name.  Which means  when people
 *              for instance  look at  it using `p`  etc., it  still introduces
 *              itself using the deleted name.  Can confuse people.
 */
VALUE rb_mod_remove_const(VALUE space, VALUE name);

/**
 * Queries if the constant is defined at the namespace.
 *
 * @param[in]  space        Target namespace.
 * @param[in]  name         Target name to query.
 * @retval     RUBY_Qtrue   There is a constant.
 * @retval     RUBY_Qfalse  No such constant.
 *
 * @internal
 *
 * The return values are not typo!  This function returns ruby values casted to
 * `int`.  Completely brain-damaged design.
 */
int rb_const_defined(VALUE space, ID name);

/**
 * Identical to rb_const_defined(), except it  doesn't look for parent classes.
 * For  instance  `Array`  is  a  toplevel  constant,  which  is  visible  from
 * everywhere.  But this  function does not take such things  into account.  It
 * concerns only what is directly defined inside of the given namespace.
 *
 * @param[in]  space        Target namespace.
 * @param[in]  name         Target name to query.
 * @retval     RUBY_Qtrue   There is a constant.
 * @retval     RUBY_Qfalse  No such constant.
 *
 * @internal
 *
 * The return values are not typo!  This function returns ruby values casted to
 * `int`.  Completely brain-damaged design.
 */
int rb_const_defined_at(VALUE space, ID name);

/**
 * Identical  to  rb_const_defined(),  except  it  returns  false  for  private
 * constants.
 *
 * @param[in]  space        Target namespace.
 * @param[in]  name         Target name to query.
 * @retval     RUBY_Qtrue   There is a constant.
 * @retval     RUBY_Qfalse  No such constant.
 *
 * @internal
 *
 * What does "from" mean?  The name sounds quite cryptic.
 *
 * The return values are not typo!  This function returns ruby values casted to
 * `int`.  Completely brain-damaged design.
 */
int rb_const_defined_from(VALUE space, ID name);

/**
 * Identical to rb_const_defined(), except it returns the actual defined value.
 *
 * @param[in]  space          Target namespace.
 * @param[in]  name           Target name to query.
 * @exception  rb_eNameError  No such constant.
 * @return     The defined constant.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
VALUE rb_const_get(VALUE space, ID name);

/**
 * Identical  to rb_const_defined_at(),  except it  returns the  actual defined
 * value.  It can also be seen as a routine identical to rb_const_get(), except
 * it doesn't look for parent classes.
 *
 * @param[in]  space          Target namespace.
 * @param[in]  name           Target name to query.
 * @exception  rb_eNameError  No such constant.
 * @return     The defined constant.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
VALUE rb_const_get_at(VALUE space, ID name);

/**
 * Identical  to rb_const_defined_at(),  except it  returns the  actual defined
 * value.  It can also be seen as a routine identical to rb_const_get(), except
 * it doesn't return a private constant.
 *
 * @param[in]  space          Target namespace.
 * @param[in]  name           Target name to query.
 * @exception  rb_eNameError  No such constant.
 * @return     The defined constant.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
VALUE rb_const_get_from(VALUE space, ID name);

/**
 * Names a constant.
 *
 * @param[out]  space          Target namespace.
 * @param[in]   name           Target name to query.
 * @param[in]   val            Value to define.
 * @exception   rb_eTypeError  `space` is not a module.
 * @post        `name` is a constant under `space`, whose value is `val`.
 * @note        You can reassign.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
void rb_const_set(VALUE space, ID name, VALUE val);

/**
 * Identical to rb_mod_remove_const(), except it takes the name as ::ID instead
 * of ::VALUE.
 *
 * @param[out]  space  Target namespace.
 * @param[in]   name   Variable name to remove, either in Symbol or String.
 * @return      What was removed.
 * @pre         Constant named `space::name` is deleted.
 * @note        In case what was removed was in  fact a module or a class, this
 *              operation does  not affect its  name.  Which means  when people
 *              for instance  look at  it using `p`  etc., it  still introduces
 *              itself using the deleted name.  Can confuse people.
 */
VALUE rb_const_remove(VALUE space, ID name);

#if 0 /* EXPERIMENTAL: remove if no problem */
RBIMPL_ATTR_NORETURN()
/**
 * This is the default implementation of `Module#const_missing`.
 *
 * @param[in]  space          Target namespace.
 * @param[in]  name           Target name that is nonexistent.
 * @exception  rb_eNameError  Always.
 */
VALUE rb_mod_const_missing(VALUE space, VALUE name);
#endif

/**
 * Queries if the given class has the given class variable.
 *
 * @param[in]  klass        Target class.
 * @param[in]  name         Name to query.
 * @return     RUBY_Qtrue   Yes there is.
 * @return     RUBY_Qfalse  No there isn't.
 * @pre        `klass` must be an instance of rb_cModule.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
VALUE rb_cvar_defined(VALUE klass, ID name);

/**
 * Assigns a value to a class variable.
 *
 * @param[out]  klass  Target class.
 * @param[in]   name   Variable name.
 * @param[in]   val    Value to be assigned.
 * @post        `klass` has a class variable named `name` whose value is `val`.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
void rb_cvar_set(VALUE klass, ID name, VALUE val);

/**
 * Obtains a value from a class variable.
 *
 * @param[in]  klass             Target class.
 * @param[in]  name              Variable name.
 * @exception  rb_eNameError     Uninitialised class variable.
 * @exception  rb_eRuntimeError  `[Bug#14541]` situation.
 * @return     Class variable named `name` under `klass`.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
VALUE rb_cvar_get(VALUE klass, ID name);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical  to rb_cvar_get(),  except  it takes  additional "front"  pointer.
 * This  extra parameter  is a  buffer,  which will  have the  class where  the
 * queried class variable actually resides.
 *
 * @param[in]   klass             Target class.
 * @param[in]   name              Variable name.
 * @param[out]  front             Return buffer.
 * @exception   rb_eNameError     Uninitialised class variable.
 * @exception   rb_eRuntimeError  `[Bug#14541]` situation.
 * @return      Class variable named `name` under `klass`.
 * @post        `front` has the class object,  which is an ancestor of `klass`,
 *              where the queried class variable actually resides.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
VALUE rb_cvar_find(VALUE klass, ID name, VALUE *front);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_cvar_set(), except it accepts C's string instead of ::ID.
 *
 * @param[out]  klass  Target class.
 * @param[in]   name   Variable name.
 * @param[in]   val    Value to be assigned.
 * @post        `klass` has a class variable named `name` whose value is `val`.
 */
void rb_cv_set(VALUE klass, const char *name, VALUE val);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_cvar_get(), except it accepts C's string instead of ::ID.
 *
 * @param[in]  klass             Target class.
 * @param[in]  name              Variable name.
 * @exception  rb_eNameError     Uninitialised class variable.
 * @exception  rb_eRuntimeError  `[Bug#14541]` situation.
 * @return     Class variable named `name` under `klass`.
 */
VALUE rb_cv_get(VALUE klass, const char *name);

RBIMPL_ATTR_NONNULL(())
/**
 * @alias{rb_cv_set}
 *
 * @internal
 *
 * Am I missing something?  Why we have the same thing in different names?
 */
void rb_define_class_variable(VALUE, const char*, VALUE);

/**
 * Resembles `Module#class_variables`.   List up  the variables defined  at the
 * receiver.  This  includes the  names of constants  in any  included modules,
 * unless `argv[0]` is ::RUBY_Qfalse.
 *
 * The  implementation  makes  no  guarantees  about the  order  in  which  the
 * constants are yielded.
 *
 * @param[in]  argc  Either 0 or 1.
 * @param[in]  argv  Pointer to ::RUBY_Qfalse, if `argc == 1`.
 * @param[in]  recv  Target class.
 * @return     An  array  of symbols,  which  are  class variable  names  under
 *             `recv`.
 */
VALUE rb_mod_class_variables(int argc, const VALUE *argv, VALUE recv);

/**
 * Resembles `Module#remove_class_variable`.
 *
 * @param[out]  mod   Target class.
 * @param[in]   name  Variable name to remove, either in Symbol or String.
 * @return      What was removed.
 * @pre         Instance variable named `name` is deleted from `obj`.
 */
VALUE rb_mod_remove_cvar(VALUE mod, VALUE name);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_VARIABLE_H */
