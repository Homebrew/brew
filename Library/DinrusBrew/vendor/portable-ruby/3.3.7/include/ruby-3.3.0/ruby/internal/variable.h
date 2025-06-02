#ifndef RBIMPL_VARIABLE_H                            /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_VARIABLE_H
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
 * @brief      Declares rb_define_variable().
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/noreturn.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Type that represents a global variable getter function.
 *
 * @param[in]      id    The variable name.
 * @param[in,out]  data  Where the value is stored.
 * @return         The value that shall be visible from Ruby.
 */
typedef VALUE rb_gvar_getter_t(ID id, VALUE *data);

/**
 * Type that represents a global variable setter function.
 *
 * @param[in]      val   The value to set.
 * @param[in]      id    The variable name.
 * @param[in,out]  data  Where the value is to be stored.
 */
typedef void  rb_gvar_setter_t(VALUE val, ID id, VALUE *data);

/**
 * Type that represents a global variable marker function.
 *
 * @param[in]  var  Where the value is to be stored.
 */
typedef void  rb_gvar_marker_t(VALUE *var);

/**
 * @deprecated
 *
 * This function has no actual usage (than in ruby itself).  Please ignore.  It
 * was a bad idea to expose this function  to 3rd parties, but we can no longer
 * delete it.
 */
rb_gvar_getter_t rb_gvar_undef_getter;

/**
 * @deprecated
 *
 * This function has no actual usage (than in ruby itself).  Please ignore.  It
 * was a bad idea to expose this function  to 3rd parties, but we can no longer
 * delete it.
 */
rb_gvar_setter_t rb_gvar_undef_setter;

/**
 * @deprecated
 *
 * This function has no actual usage (than in ruby itself).  Please ignore.  It
 * was a bad idea to expose this function  to 3rd parties, but we can no longer
 * delete it.
 */
rb_gvar_marker_t rb_gvar_undef_marker;

/**
 * This is the getter function that  backs global variables defined from a ruby
 * script.  Extension  libraries can use this  if its global variable  needs no
 * custom logic.
 */
rb_gvar_getter_t rb_gvar_val_getter;

/**
 * This is the setter function that  backs global variables defined from a ruby
 * script.  Extension  libraries can use this  if its global variable  needs no
 * custom logic.
 */
rb_gvar_setter_t rb_gvar_val_setter;

/**
 * This is the setter function that  backs global variables defined from a ruby
 * script.  Extension  libraries can use this  if its global variable  needs no
 * custom logic.
 */
rb_gvar_marker_t rb_gvar_val_marker;

/**
 * @deprecated
 *
 * This function has no actual usage (than in ruby itself).  Please ignore.  It
 * was a bad idea to expose this function  to 3rd parties, but we can no longer
 * delete it.
 */
rb_gvar_getter_t rb_gvar_var_getter;

/**
 * @deprecated
 *
 * This function has no actual usage (than in ruby itself).  Please ignore.  It
 * was a bad idea to expose this function  to 3rd parties, but we can no longer
 * delete it.
 */
rb_gvar_setter_t rb_gvar_var_setter;

/**
 * @deprecated
 *
 * This function has no actual usage (than in ruby itself).  Please ignore.  It
 * was a bad idea to expose this function  to 3rd parties, but we can no longer
 * delete it.
 */
rb_gvar_marker_t rb_gvar_var_marker;

RBIMPL_ATTR_NORETURN()
/**
 * This function just raises ::rb_eNameError.   Handy when you want to prohibit
 * a global variable from being squashed by someone.
 */
rb_gvar_setter_t rb_gvar_readonly_setter;

RBIMPL_ATTR_NONNULL(())
/**
 * "Shares" a global variable between Ruby and C.  Normally a Ruby-level global
 * variable  is stored  somewhere deep  inside of  the interpreter's  execution
 * context, but this way you can explicitly specify its storage.
 *
 * ```CXX
 * static VALUE foo;
 *
 * extern "C" void
 * init_Foo(void)
 * {
 *     foo = rb_eval_string("...");
 *     rb_define_variable("$foo", &foo);
 * }
 * ```
 *
 * In the above  example a Ruby global  variable named `$foo` is stored  in a C
 * global variable named `foo`.
 *
 * @param[in]  name  Variable (Ruby side).
 * @param[in]  var   Variable (C side).
 * @post       Ruby level  global variable named  `name` is defined  if absent,
 *             and its storage is set to `var`.
 */
void rb_define_variable(const char *name, VALUE *var);

RBIMPL_ATTR_NONNULL((1))
/**
 * Defines a global variable that  is purely function-backended.  By using this
 * API a programmer can define a  global variable that dynamically changes from
 * time to time.
 *
 * @param[in]  name   Variable name, in C's string.
 * @param[in]  getter A getter function.
 * @param[in]  setter A setter function.
 * @post       Ruby level global variable named `name` is defined if absent.
 *
 * @internal
 *
 * @shyouhei doesn't know if this is an  Easter egg or an official feature, but
 * you can pass  0 to the third argument (setter).   That effectively nullifies
 * any efforts to write to the defining global variable.
 */
void rb_define_virtual_variable(const char *name, rb_gvar_getter_t *getter, rb_gvar_setter_t *setter);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to  rb_define_virtual_variable(), but can also  specify a storage.
 * A programmer can use the storage for e.g.  memoisation, storing intermediate
 * computation result, etc.
 *
 * Also you can pass 0 to this function, unlike other variants:
 *
 *   - When getter is 0 ::rb_gvar_var_getter is used instead.
 *   - When setter is 0 ::rb_gvar_var_setter is used instead.
 *   - When data is 0, you must  specify a non-zero setter function.  Otherwise
 *     ::rb_gvar_var_setter tries to write to `*NULL`, and just causes SEGV.
 *
 * @param[in]  name   Variable name, in C's string.
 * @param[in]  var    Variable storage.
 * @param[in]  getter A getter function.
 * @param[in]  setter A setter function.
 * @post       Ruby level global variable named `name` is defined if absent.
 */
void rb_define_hooked_variable(const char *name, VALUE *var, rb_gvar_getter_t *getter, rb_gvar_setter_t *setter);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_define_variable(), except it does not allow Ruby programs to
 * assign values  to such  global variable.   C codes can  still set  values at
 * will.   This  could be  handy  for  you  when implementing  an  `errno`-like
 * experience, where  a method updates a  read-only global variable as  a side-
 * effect.
 *
 * @param[in]  name  Variable (Ruby side).
 * @param[in]  var   Variable (C side).
 * @post       Ruby level  global variable named  `name` is defined  if absent,
 *             and its storage is set to `var`.
 */
void rb_define_readonly_variable(const char *name, const VALUE *var);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines a Ruby level constant under a namespace.
 *
 * @param[out]  klass            Namespace for the constant to reside.
 * @param[in]   name             Name of the constant.
 * @param[in]   val              Value of the constant.
 * @exception   rb_eTypeError    `klass` is not a kind of ::rb_cModule.
 * @exception   rb_eFrozenError  `klass` is frozen.
 * @post        Ruby level constant `klass::name` is defined to be `val`.
 * @note        This API  does not stop  you from  defining a constant  that is
 *              unable  to   reach  from   ruby  (like  for   instance  passing
 *              non-capital letter to `name`).
 * @note        This API  does not  stop you from  overwriting a  constant that
 *              already exist.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
void rb_define_const(VALUE klass, const char *name, VALUE val);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical  to  rb_define_const(),  except   it  defines  that  of  "global",
 * i.e. toplevel constant.
 *
 * @param[in]   name             Name of the constant.
 * @param[in]   val              Value of the constant.
 * @exception   rb_eFrozenError  ::rb_cObject is frozen.
 * @post        Ruby level constant \::name is defined to be `val`.
 * @note        This API  does not stop  you from  defining a constant  that is
 *              unable  to   reach  from   ruby  (like  for   instance  passing
 *              non-capital letter to `name`).
 * @note        This API  does not  stop you from  overwriting a  constant that
 *              already exist.
 */
void rb_define_global_const(const char *name, VALUE val);

RBIMPL_ATTR_NONNULL(())
/**
 * Asserts  that the  given  constant  is deprecated.   Attempt  to refer  such
 * constant will produce a warning.
 *
 * @param[in]  mod              Namespace of the target constant.
 * @param[in]  name             Name of the constant.
 * @exception  rb_eNameError    No such constant.
 * @exception  rb_eFrozenError  `mod` is frozen.
 * @post       `name` under `mod` is deprecated.
 */
void rb_deprecate_constant(VALUE mod, const char *name);

RBIMPL_ATTR_NONNULL(())
/**
 * Assigns to a global variable.
 *
 * @param[in]  name  Target global variable.
 * @param[in]  val   Value to assign.
 * @return     Passed value.
 * @post       Ruby level  global variable named  `name` is defined  if absent,
 *             whose value is set to `val`.
 *
 * @internal
 *
 * Above  description  is  in  fact   inaccurate.   This  API  interfaces  with
 * `set_trace_func`.
 */
VALUE rb_gv_set(const char *name, VALUE val);

RBIMPL_ATTR_NONNULL(())
/**
 * Obtains a global variable.
 *
 * @param[in]  name       Global variable to query.
 * @retval     RUBY_Qnil  The global variable does not exist.
 * @retval     otherwise  The value assigned to the global variable.
 *
 * @internal
 *
 * Unlike rb_gv_set(), there is no way to trace this function.
 */
VALUE rb_gv_get(const char *name);

RBIMPL_ATTR_NONNULL(())
/**
 * Obtains an instance variable.
 *
 * @param[in]  obj                Target object.
 * @param[in]  name               Target instance variable to query.
 * @exception  rb_eEncodingError  `name` is corrupt (contains Hanzi etc.).
 * @retval     RUBY_nil           No such instance variable.
 * @retval     otherwise          The value assigned to the instance variable.
 */
VALUE rb_iv_get(VALUE obj, const char *name);

RBIMPL_ATTR_NONNULL(())
/**
 * Assigns to an instance variable.
 *
 * @param[out]  obj                Target object.
 * @param[in]   name               Target instance variable.
 * @param[in]   val                Value to assign.
 * @exception   rb_eFrozenError    Can't modify `obj`.
 * @exception   rb_eArgError       `obj` has too many instance variables.
 * @return      Passed value.
 * @post        An  instance variable  named  `name` is  defined  if absent  on
 *              `obj`, whose value is set to `val`.
 *
 * @internal
 *
 * This function does not stop you form creating an ASCII-incompatible instance
 * variable, but there is no way to get one because rb_iv_get raises exceptions
 * for such things.  This design seems broken...  But no idea why.
 */
VALUE rb_iv_set(VALUE obj, const char *name, VALUE val);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_VARIABLE_H */
