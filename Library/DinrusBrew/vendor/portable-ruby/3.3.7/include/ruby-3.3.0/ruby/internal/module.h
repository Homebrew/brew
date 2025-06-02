#ifndef RBIMPL_MODULE_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_MODULE_H
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
 * @brief      Creation and modification of Ruby modules.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

/**
 * @defgroup  class  Classes and their hierarchy.
 *
 * @par Terminology
 *   - class: same as in Ruby.
 *   - singleton class: class for a particular object.
 *   - eigenclass: = singleton class
 *   - metaclass: class of a class.  Metaclass is a kind of singleton class.
 *   - metametaclass: class of a metaclass.
 *   - meta^(n)-class: class of a meta^(n-1)-class.
 *   - attached object: A singleton class knows its unique instance.
 *     The instance is called the attached object for the singleton class.
 * @{
 */

RBIMPL_SYMBOL_EXPORT_BEGIN()

RBIMPL_ATTR_NONNULL(())
/**
 * Defines a top-level class.
 *
 * @param[in]  name           Name of the class.
 * @param[in]  super          A class from which the new class will derive.
 * @exception  rb_eTypeError  The constant name `name` is already taken but the
 *                            constant is not a class.
 * @exception  rb_eTypeError  The class  is already  defined but the  class can
 *                            not  be reopened  because its  superclass is  not
 *                            `super`.
 * @exception  rb_eArgError   `super` is NULL.
 * @return     The created class.
 * @post       Top-level constant named `name` refers the returned class.
 * @note       If a class named `name` is already defined and its superclass is
 *             `super`, the function just returns the defined class.
 * @note       The  compaction  GC  does  not move  classes  returned  by  this
 *             function.
 *
 * @internal
 *
 * There are classes without names, but you  can't pass NULL here.  You have to
 * use other ways to create one.
 */
VALUE rb_define_class(const char *name, VALUE super);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines a top-level module.
 *
 * @param[in]  name           Name of the module.
 * @exception  rb_eTypeError  The constant name `name` is already taken but the
 *                            constant is not a module.
 * @return     The created module.
 * @post       Top-level constant named `name` refers the returned module.
 * @note       The  compaction  GC  does  not move  classes  returned  by  this
 *             function.
 *
 * @internal
 *
 * There are modules without names, but you  can't pass NULL here.  You have to
 * use other ways to create one.
 */
VALUE rb_define_module(const char *name);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines a class under the namespace of `outer`.
 *
 * @param[out]  outer          A class which contains the new class.
 * @param[in]   name           Name of the new class
 * @param[in]   super          A class from which the new class will derive.
 *                             0 means ::rb_cObject.
 * @exception   rb_eTypeError  The constant  name `name`  is already  taken but
 *                             the constant is not a class.
 * @exception   rb_eTypeError  The class  is already defined but  the class can
 *                             not be  reopened because  its superclass  is not
 *                             `super`.
 * @exception   rb_eArgError   `super` is NULL.
 * @return      The created class.
 * @post        `outer::name` refers the returned class.
 * @note        If a class  named `name` is already defined  and its superclass
 *              is `super`, the function just returns the defined class.
 * @note        The  compaction  GC does  not  move  classes returned  by  this
 *              function.
 */
VALUE rb_define_class_under(VALUE outer, const char *name, VALUE super);

RBIMPL_ATTR_NONNULL(())
/**
 * Defines a module under the namespace of `outer`.
 *
 * @param[out]  outer          A class which contains the new module.
 * @param[in]   name           Name of the new module
 * @exception   rb_eTypeError  The constant  name `name`  is already  taken but
 *                             the constant is not a class.
 * @return      The created module.
 * @post        `outer::name` refers the returned module.
 * @note        The  compaction  GC does  not  move  classes returned  by  this
 *              function.
 */
VALUE rb_define_module_under(VALUE outer, const char *name);

/**
 * Includes a module to a class.
 *
 * @param[out]  klass         Inclusion destination.
 * @param[in]   module        Inclusion source.
 * @exception   rb_eArgError  Cyclic inclusion.
 *
 * @internal
 *
 * :FIXME: @shyouhei suspects this function  lacks assertion that the arguments
 * being modules...  Could silently SEGV if non-module was passed?
 */
void rb_include_module(VALUE klass, VALUE module);

/**
 * Extend the object with the module.
 *
 * @warning     This    is   the    same    as   `Module#extend_object`,    not
 *              `Object#extend`!  These  two methods are very  similar, but not
 *              identical.  The difference is the hook.  `Module#extend_object`
 *              does not invoke `Module#extended`, while `Object#extend` does.
 * @param[out]  obj  Object to extend.
 * @param[in]   mod  Module of extension.
 */
void rb_extend_object(VALUE obj, VALUE mod);

/**
 * Identical to rb_include_module(), except it  "prepends" the passed module to
 * the klass,  instead of  includes.  This affects  how `super`  resolves.  For
 * instance:
 *
 * ```ruby
 * class  Q;                def foo;      "<q/>"       end end
 * module W;                def foo; "<w>#{super}</w>" end end
 * class  E < Q; include W; def foo; "<e>#{super}</e>" end end
 * class  R < Q; prepend W; def foo; "<r>#{super}</r>" end end
 *
 * E.new.foo # => "<e><w><q/></w></e>"
 * r.new.foo # => "<W><r><q/></r></w>"
 * ```
 *
 * @param[out]  klass         Target class to modify.
 * @param[in]   module        Module to prepend.
 * @exception   rb_eArgError  Cyclic inclusion.
 */
void rb_prepend_module(VALUE klass, VALUE module);

/** @} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_MODULE_H */
