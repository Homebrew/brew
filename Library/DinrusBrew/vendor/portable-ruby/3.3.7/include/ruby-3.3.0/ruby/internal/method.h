#ifndef RBIMPL_METHOD_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_METHOD_H
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
 * @brief      Creation and modification of Ruby methods.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/backward/2/stdarg.h"

/**
 * @defgroup  defmethod  Defining methods
 *
 * There are some APIs to define a method from C.
 * These API takes a C function as a method body.
 *
 * ### Method body functions
 *
 * Method body functions must return a VALUE and
 * can be one of the following form:
 *
 * #### Fixed number of parameters
 *
 * This form is a normal C function, excepting it takes
 * a receiver object as the first argument.
 *
 * ```CXX
 * static VALUE my_method(VALUE self, VALUE x, VALUE y);
 * ```
 *
 * #### argc and argv style
 *
 * This form takes three parameters: argc, argv and self.
 * self is the receiver. argc is the number of arguments.
 * argv is a pointer to an array of the arguments.
 *
 * ```CXX
 * static VALUE my_method(int argc, VALUE *argv, VALUE self);
 * ```
 *
 * #### Ruby array style
 *
 * This form takes two parameters: self and args.
 * self is the receiver. args is an Array object which
 * contains the arguments.
 *
 * ```CXX
 * static VALUE my_method(VALUE self, VALUE args);
 * ```
 *
 * ### Number of parameters
 *
 * Method defining APIs takes the number of parameters which the
 * method will takes. This number is called argc.
 * argc can be:
 *
 *   - Zero or positive number.
 *     This means the method body function takes a fixed number of parameters.
 *
 *   - `-1`.
 *     This means the method body function is "argc and argv" style.
 *
 *   - `-2`.
 *     This means the method body function is "self and args" style.
 *
 * @{
 */

RBIMPL_SYMBOL_EXPORT_BEGIN()

RBIMPL_ATTR_NONNULL(())
/**
 * Defines a method.
 *
 * @param[out]  klass  A module or a class.
 * @param[in]   mid    Name of the function.
 * @param[in]   func   The method body.
 * @param[in]   arity  The number of parameters.  See @ref defmethod.
 * @note        There are in fact 18 different prototypes for func.
 * @see         ::ruby::backward::cxxanyargs::define_method::rb_define_method
 */
void rb_define_method(VALUE klass, const char *mid, VALUE (*func)(ANYARGS), int arity);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines a module function for a module.
 *
 * @param[out]  klass  A module or a class.
 * @param[in]   mid    Name of the function.
 * @param[in]   func   The method body.
 * @param[in]   arity  The number of parameters.  See @ref defmethod.
 * @note        There are in fact 18 different prototypes for func.
 * @see         ::ruby::backward::cxxanyargs::define_method::rb_define_module_function
 */
void rb_define_module_function(VALUE klass, const char *mid, VALUE (*func)(ANYARGS), int arity);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines a global function.
 *
 * @param[in]  mid    Name of the function.
 * @param[in]  func   The method body.
 * @param[in]  arity  The number of parameters.  See @ref defmethod.
 * @note       There are in fact 18 different prototypes for func.
 * @see        ::ruby::backward::cxxanyargs::define_method::rb_define_global_function
 */
void rb_define_global_function(const char *mid, VALUE (*func)(ANYARGS), int arity);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines an undef of a method.  -- What?
 *
 * In ruby, there are two separate concepts called "undef" and "remove_method".
 * The thing you imagine when you  "un-define" a method is remove_method.  This
 * one on the  other hand is masking of a  previous method definition.  Suppose
 * for instance:
 *
 * ```ruby
 * class Foo
 *   def foo
 *   end
 * end
 *
 * class Bar < Foo
 *   def bar
 *     foo
 *   end
 * end
 *
 * class Baz < Foo
 *   undef foo            # <--- (*1)
 * end
 * ```
 *
 * This `undef foo` at `(*1)` must not eliminate `Foo#foo`, because that method
 * is also used from `Bar#bar`.  So  instead of physically executing the target
 * method, `undef` inserts  a special filtering entry to the  class (`Baz` this
 * case).  That entry,  when called, acts as  if there were no  methods at all.
 * But the original can still be accessible, via ways like `Bar#bar` above.
 *
 * @param[out]  klass            The class to insert an undef.
 * @param[in]   name             Name of the undef.
 * @exception   rb_eTypeError    `klass` is a non-module.
 * @exception   rb_eFrozenError  `klass` is frozen.
 * @see         rb_remove_method
 */
void rb_undef_method(VALUE klass, const char *name);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines an alias of a method.
 *
 * @param[in,out]  klass            The class which the original method belongs
 *                                  to; this is also  where the new method will
 *                                  belong to.
 * @param[in]      dst              A new name for the method.
 * @param[in]      src              The original name of the method.
 * @exception      rb_eTypeError    `klass` is a non-module.
 * @exception      rb_eFrozenError  `klass` is frozen.
 * @exception      rb_eNameError    There is  no such method named  as `src` in
 *                                  `klass`.
 *
 * @internal
 *
 * Above  description  is   in  fact  a  bit  inaccurate   because  it  ignores
 * Refinements.
 */
void rb_define_alias(VALUE klass, const char *dst, const char *src);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines public accessor method(s) for an attribute.
 *
 * @param[out]  klass            The class which the attribute will belong to.
 * @param[in]   name             Name of the attribute.
 * @param[in]   read             Whether to define a getter method.
 * @param[in]   write            Whether to define a setter method.
 * @exception   rb_eTypeError    `klass` is a non-module.
 * @exception   rb_eFrozenError  `klass` is frozen.
 * @exception   rb_eNameError    `name` invalid as an attr e.g. an operator.
 */
void rb_define_attr(VALUE klass, const char *name, int read, int write);

/** @} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_METHOD_H */
