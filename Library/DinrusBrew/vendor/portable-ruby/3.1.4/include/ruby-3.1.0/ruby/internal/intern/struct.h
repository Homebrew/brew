#ifndef RBIMPL_INTERN_STRUCT_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_STRUCT_H
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
 * @brief      Public APIs related to ::rb_cStruct.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/intern/vm.h" /* rb_alloc_func_t */
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* struct.c */

/**
 * Creates an instance of the given struct.
 *
 * @param[in]  klass  The class of the instance to allocate.
 * @param[in]  ...    The fields.
 * @return     Allocated instance of `klass`.
 * @pre        `klass` must be a subclass of ::rb_cStruct.
 * @note       Number of variadic arguments must much that of the passed klass'
 *             fields.
 */
VALUE rb_struct_new(VALUE klass, ...);

/**
 * Defines a struct class.
 *
 * @param[in]  name           Name of the class.
 * @param[in]  ...            Arbitrary number of  `const char*`, terminated by
 *                            zero.  Each of which are the name of fields.
 * @exception  rb_eNameError  `name` is not a constant name.
 * @exception  rb_eTypeError  `name` is already taken.
 * @exception  rb_eArgError    Duplicated field name.
 * @return     The defined class.
 * @post       Global toplevel constant `name` is defined.
 * @note       `name` is allowed  to be a null pointer.   This function creates
 *             an anonymous struct class then.
 *
 * @internal
 *
 * Not  seriously  checked but  it  seems  this  function  does not  share  its
 * implementation with how `Struct.new` is implemented...?
 */
VALUE rb_struct_define(const char *name, ...);

RBIMPL_ATTR_NONNULL((2))
/**
 * Identical  to rb_struct_define(),  except  it defines  the  class under  the
 * specified namespace instead of global toplevel.
 *
 * @param[out]  space          Namespace that the defining class shall reside.
 * @param[in]   name           Name of the class.
 * @param[in]   ...            Arbitrary number of `const char*`, terminated by
 *                             zero.  Each of which are the name of fields.
 * @exception   rb_eNameError  `name` is not a constant name.
 * @exception   rb_eTypeError  `name` is already taken.
 * @exception   rb_eArgError    Duplicated field name.
 * @return      The defined class.
 * @post        `name` is a constant under `space`.
 * @note        In contrast to rb_struct_define(), it doesn't make any sense to
 *              pass  a null pointer to this function.
 */
VALUE rb_struct_define_under(VALUE space, const char *name, ...);

/**
 * Identical to  rb_struct_new(), except it  takes the  field values as  a Ruby
 * array.
 *
 * @param[in]  klass   The class of the instance to allocate.
 * @param[in]  values  Field values.
 * @return     Allocated instance of `klass`.
 * @pre        `klass` must be a subclass of ::rb_cStruct.
 * @pre        `values` must be an instance of struct ::RArray.
 */
VALUE rb_struct_alloc(VALUE klass, VALUE values);

/**
 * Mass-assigns a struct's fields.
 *
 * @param[out]  self    An instance of a struct class to squash.
 * @param[in]   values  New values.
 * @return      ::RUBY_Qnil.
 */
VALUE rb_struct_initialize(VALUE self, VALUE values);

/**
 * Identical to rb_struct_aref(), except it takes ::ID instead of ::VALUE.
 *
 * @param[in]  self           An instance of a struct class.
 * @param[in]  key            Key to query.
 * @exception  rb_eTypeError  `self` is not a struct.
 * @exception  rb_eNameError  No such field.
 * @return     The value stored at `key` in `self`.
 */
VALUE rb_struct_getmember(VALUE self, ID key);

/**
 * Queries the list of the names of the fields of the given struct class.
 *
 * @param[in]  klass  A subclass of ::rb_cStruct.
 * @return     The list of the names of the fields of `klass`.
 */
VALUE rb_struct_s_members(VALUE klass);

/**
 * Queries the list of the names of the fields of the class of the given struct
 * object.  This is  almost the same as calling  rb_struct_s_members() over the
 * class of the receiver.
 *
 * @internal
 *
 * "Almost"?  What exactly is the difference?
 *
 * @endinternal
 *
 * @param[in]  self  An instance of a subclass of ::rb_cStruct.
 * @return     The list of the names of the fields.
 */
VALUE rb_struct_members(VALUE self);

/**
 * Allocates an  instance of the  given class.   This consequential name  is of
 * course because rb_struct_alloc() not only  allocates but also initialises an
 * instance.  The API design is broken.
 *
 * @param[in]  klass  A subclass of ::rb_cStruct.
 * @return     An allocated instance of `klass`, not initialised.
 */
VALUE rb_struct_alloc_noinit(VALUE klass);

/**
 * Identical to rb_struct_define(), except it does not define accessor methods.
 * You  have to  define them  yourself.   Forget about  the allocator  function
 * parameter; it is  for internal use only.  Extension libraries  are unable to
 * properly allocate a ruby struct, because `RStruct` is opaque.
 *
 * @internal
 *
 * Several flags must be set up properly for ::RUBY_T_STRUCT objects, which are
 * also missing for extension libraries.
 *
 * @endinternal
 *
 * @param[in]  name           Name of the class.
 * @param[in]  super          Superclass of the defining class.
 * @param[in]  func           Must be 0 for extension libraries.
 * @param[in]  ...            Arbitrary number of  `const char*`, terminated by
 *                            zero.  Each of which are the name of fields.
 * @exception  rb_eNameError  `name` is not a constant name.
 * @exception  rb_eTypeError  `name` is already taken.
 * @exception  rb_eArgError    Duplicated field name.
 * @return     The defined class.
 * @post       Global toplevel constant `name` is defined.
 * @note       `name` is allowed  to be a null pointer.   This function creates
 *             an anonymous struct class then.
 */
VALUE rb_struct_define_without_accessor(const char *name, VALUE super, rb_alloc_func_t func, ...);

RBIMPL_ATTR_NONNULL((2))
/**
 * Identical  to  rb_struct_define_without_accessor(),  except it  defines  the
 * class under the specified namespace instead of global toplevel.  It can also
 * be seen as  a routine identical to rb_struct_define_under(),  except it does
 * not define accessor methods.
 *
 * @param[out]  outer          Namespace that the defining class shall reside.
 * @param[in]   class_name     Name of the class.
 * @param[in]   super          Superclass of the defining class.
 * @param[in]   alloc          Must be 0 for extension libraries.
 * @param[in]   ...            Arbitrary number of `const char*`, terminated by
 *                             zero.  Each of which are the name of fields.
 * @exception   rb_eNameError  `class_name` is not a constant name.
 * @exception   rb_eTypeError  `class_name` is already taken.
 * @exception   rb_eArgError    Duplicated field name.
 * @return      The defined class.
 * @post        `class_name` is a constant under `outer`.
 * @note        In contrast to  rb_struct_define_without_accessor(), it doesn't
 *              make any sense to pass a null name.
 */
VALUE rb_struct_define_without_accessor_under(VALUE outer, const char *class_name, VALUE super, rb_alloc_func_t alloc, ...);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_STRUCT_H */
