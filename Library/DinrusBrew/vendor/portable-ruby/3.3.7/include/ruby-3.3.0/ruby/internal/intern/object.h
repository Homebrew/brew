#ifndef RBIMPL_INTERN_OBJECT_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_OBJECT_H
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
 * @brief      Public APIs related to ::rb_cObject.
 */
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * This macro is (used but) mysterious.  Why on earth do we need this?
 *
 * - `obj != orig` check is done anyways inside of rb_obj_init_copy().
 * - rb_obj_init_copy() returns something.  No need are there to add `, 1`.
 */
#define RB_OBJ_INIT_COPY(obj, orig) \
    ((obj) != (orig) && (rb_obj_init_copy((obj), (orig)), 1))
/** @old{RB_OBJ_INIT_COPY} */
#define OBJ_INIT_COPY(obj, orig) RB_OBJ_INIT_COPY(obj, orig)

/* object.c */

/**
 * Identical to  rb_class_new_instance(), except it passes  the passed keywords
 * if any to the `#initialize` method.
 *
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           Arbitrary number of method arguments.
 * @param[in]  klass          An instance of ::rb_cClass.
 * @exception  rb_eTypeError  `klass`'s allocator is undefined.
 * @exception  rb_eException  Any exceptions can happen inside.
 * @return     An allocated new instance of `klass`.
 * @note       This is _the_ implementation of `Object.new`.
 */
VALUE rb_class_new_instance_pass_kw(int argc, const VALUE *argv, VALUE klass);

/**
 * Allocates, then initialises an instance of  the given class.  It first calls
 * the passed  class' allocator to  obtain an uninitialised object,  then calls
 * its initialiser with the remaining arguments.
 *
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           Arguments passed to `#initialize`.
 * @param[in]  klass          An instance of ::rb_cClass.
 * @exception  rb_eTypeError  `klass`'s allocator is undefined.
 * @exception  rb_eException  Any exceptions can happen inside.
 * @return     An allocated new instance of `klass`.
 */
VALUE rb_class_new_instance(int argc, const VALUE *argv, VALUE klass);

/**
 * Identical to rb_class_new_instance(),  except you can specify  how to handle
 * the last element of the given array.
 *
 * @param[in]  argc             Number of objects of `argv`.
 * @param[in]  argv             Arbitrary number of method arguments.
 * @param[in]  klass            An instance of ::rb_cClass.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception  rb_eTypeError    `klass`'s allocator is undefined.
 * @exception  rb_eException    Any exceptions can happen inside.
 * @return     An allocated new instance of `klass`.
 */
VALUE rb_class_new_instance_kw(int argc, const VALUE *argv, VALUE klass, int kw_splat);

/**
 * Checks for equality of the passed objects, in terms of `Object#eql?`.
 *
 * @param[in]  lhs          Comparison left hand side.
 * @param[in]  rhs          Comparison right hand side.
 * @retval     non-zero     They are equal.
 * @retval     0            Otherwise.
 * @note       This  function  actually  calls `lhs.eql?(rhs)`  so  you  cannot
 *             implement your class' `#eql?` method using it.
 */
int rb_eql(VALUE lhs, VALUE rhs);

/**
 * Generates a textual representation of the given object.
 *
 * @param[in]  obj  Arbitrary ruby object.
 * @return     An instance of ::rb_cString that represents `obj`.
 * @note       This is  the default  implementation of `Object#to_s`  that each
 *             subclasses want to override.
 */
VALUE rb_any_to_s(VALUE obj);

/**
 * Generates a human-readable textual representation of the given object.  This
 * is  largely similar  to Ruby  level `Object#inspect`  but not  the same;  it
 * additionally escapes the inspection result  so that the string be compatible
 * with that of default internal (or default external, if absent).
 *
 * @param[in]  obj  Arbitrary ruby object.
 * @return     An instance of ::rb_cString that represents `obj`.
 */
VALUE rb_inspect(VALUE obj);

/**
 * Queries if the given object is a direct instance of the given class.
 *
 * @param[in]  obj            Arbitrary ruby object.
 * @param[in]  klass          An instance of ::rb_cModule.
 * @exception  rb_eTypeError  `klass` is neither module nor class.
 * @retval     RUBY_Qtrue     `obj` is an instance of `klass`.
 * @retval     RUBY_Qfalse    Otherwise.
 */
VALUE rb_obj_is_instance_of(VALUE obj, VALUE klass);

/**
 * Queries if the given object is  an instance (of possibly descendants) of the
 * given class.
 *
 * @param[in]  obj            Arbitrary ruby object.
 * @param[in]  klass          An instance of ::rb_cModule.
 * @exception  rb_eTypeError  `klass` is neither module nor class.
 * @retval     RUBY_Qtrue     `obj` is a `klass`.
 * @retval     RUBY_Qfalse    Otherwise.
 */
VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);

/**
 * Allocates an instance of the given class.
 *
 * @param[in]  klass          A class to instantiate.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @return     An allocated, not yet initialised instance of `klass`.
 * @note       It calls  the allocator defined by  rb_define_alloc_func().  You
 *             cannot  use   this  function   to  define  an   allocator.   Use
 *             rb_newobj_of(), #TypedData_Make_Struct or others, instead.
 * @note       Usually  prefer  rb_class_new_instance() to  rb_obj_alloc()  and
 *             rb_obj_call_init().
 * @see        rb_class_new_instance()
 * @see        rb_obj_call_init()
 * @see        rb_define_alloc_func()
 * @see        rb_newobj_of()
 * @see        #TypedData_Make_Struct
 */
VALUE rb_obj_alloc(VALUE klass);

/**
 * Produces a shallow copy of the given object.  Its list of instance variables
 * are copied, but  not the objects they reference.  It  also copies the frozen
 * value state.
 *
 * @param[in]  obj            Arbitrary ruby object.
 * @exception  rb_eException  `#initialize_copy` can raise anything.
 * @return     A "clone" of `obj`.
 *
 * @internal
 *
 * Unlike ruby-level `Object#clone`, there is no way to control the frozen-ness
 * of the return value.
 */
VALUE rb_obj_clone(VALUE obj);

/**
 * Duplicates  the  given   object.   This  does  almost  the   same  thing  as
 * rb_obj_clone() do.  However  it does not copy the singleton  class (if any).
 * It also doesn't copy frozen-ness.
 *
 * @param[in]  obj            Arbitrary ruby object.
 * @exception  rb_eException  `#initialize_copy` can raise anything.
 * @return     A shallow copy of `obj`.
 */
VALUE rb_obj_dup(VALUE obj);

/**
 * Default   implementation   of  `#initialize_copy`,   `#initialize_dup`   and
 * `#initialize_clone`.  It  does almost  nothing.  Just raises  exceptions for
 * checks.
 *
 * @param[in]  dst              The destination object.
 * @param[in]  src              The source object.
 * @exception  rb_eFrozenError  `dst` is frozen.
 * @exception  rb_eTypeError    `dst` and `src` have different classes.
 * @return     Always returns `dst`.
 */
VALUE rb_obj_init_copy(VALUE src, VALUE dst);

/**
 * Just  calls  rb_obj_freeze_inline() inside.   Does  this  make any  sens  to
 * extension libraries?
 *
 * @param[out]  obj  Object to freeze.
 * @return      Verbatim `obj`.
 */
VALUE rb_obj_freeze(VALUE obj);

RBIMPL_ATTR_PURE()
/**
 * Just calls  RB_OBJ_FROZEN() inside.   Does this make  any sens  to extension
 * libraries?
 *
 * @param[in]  obj          Object in question.
 * @retval     RUBY_Qtrue   Yes it is.
 * @retval     RUBY_Qfalse  No it isn't.
 */
VALUE rb_obj_frozen_p(VALUE obj);

/* gc.c */

/**
 * Finds or  creates an integer  primary key of the  given object.  In  the old
 * days  this  function  was  a  purely  arithmetic  operation  that  maps  the
 * underlying memory  address where the  object resides into a  Ruby's integer.
 * Some time around  2.x this changed.  It no longer  relates its return values
 * to C level pointers.  This function  assigns some random number to the given
 * object  if absent.   The  same number  will be  returned  on all  subsequent
 * requests.  No two active objects share a number.
 *
 * @param[in]  obj  Arbitrary ruby object.
 * @return     An instance of ::rb_cInteger which is an "identifier" of `obj`.
 *
 * @internal
 *
 * The "some  random number" is  in fact a  monotonic-increasing process-global
 * unique integer, much like an  `INTEGER AUTO_INCREMENT PRIMARY KEY` column in
 * a MySQL table.
 */
VALUE rb_obj_id(VALUE obj);

RBIMPL_ATTR_CONST()
/**
 * Identical to rb_obj_id(), except it hesitates from allocating a new instance
 * of ::rb_cInteger.  rb_obj_id() could allocate ::RUBY_T_BIGNUM objects.  That
 * allocation  might  perhaps  impact  negatively.  On  such  situations,  this
 * function  instead returns  one-shot temporary  small integers  that need  no
 * allocations at all.  The values are  guaranteed unique at the moment, but no
 * future promise  is made; could  be reused.  Use of  this API should  be very
 * instant.  It is a failure to store the returned integer to somewhere else.
 *
 * In short it is difficult to use.
 *
 * @param[in]  obj  Arbitrary ruby object.
 * @return     An instance of ::rb_cInteger unique at the moment.
 *
 * @internal
 *
 * This is roughly the old behaviour of rb_obj_id().
 */
VALUE rb_memory_id(VALUE obj);

/* object.c */

RBIMPL_ATTR_PURE()
/**
 * Finds a "real" class.  As the name  implies there are class objects that are
 * surreal.   This function  takes a  class, traverses  its ancestry  tree, and
 * returns  its nearest  ancestor which  is neither  a module  nor a  singleton
 * class.
 *
 * @param[in]  klass        An instance of ::rb_cClass.
 * @retval     RUBY_Qfalse  No real class in `klass`' ancestry tree.
 * @retval     klass        `klass` itself is a real class.
 * @retval     otherwise    Nearest ancestor of `klass` who is real.
 */
VALUE rb_class_real(VALUE klass);

RBIMPL_ATTR_PURE()
/**
 * Determines if the given two modules are relatives.
 *
 * @param[in]  scion          Possible subclass.
 * @param[in]  ascendant      Possible superclass.
 * @exception  rb_eTypeError  `ascendant` is not a module.
 * @retval     RUBY_Qtrue     `scion` inherits, or is equal to `ascendant`.
 * @retval     RUBY_Qfalse    `ascendant` inherits `scion`.
 * @retval     RUBY_Qnil      They are not relatives.
 */
VALUE rb_class_inherited_p(VALUE scion, VALUE ascendant);

RBIMPL_ATTR_PURE()
/**
 * Queries the parent of the given class.
 *
 * @param[in]  klass          A child class.
 * @exception  rb_eTypeError  `klass` is a `Class.allocate`.
 * @retval     RUBY_Qfalse    `klass` has no superclass.
 * @retval     otherwise      `klass`' superclass.
 *
 * @internal
 *
 * Is there any class except ::rb_cBasicObject, that has no superclass?
 */
VALUE rb_class_superclass(VALUE klass);

RBIMPL_ATTR_NONNULL(())
/**
 * Converts an object into another type.  Calls the specified conversion method
 * if necessary.
 *
 * @param[in]  val            An object to convert.
 * @param[in]  type           A value of enum ::ruby_value_type.
 * @param[in]  name           Name to display on error (e.g. "Array").
 * @param[in]  mid            Conversion method (e.g. "to_ary").
 * @exception  rb_eTypeError  Failed to convert.
 * @return     An object of the specified type.
 */
VALUE rb_convert_type(VALUE val, int type, const char *name, const char *mid);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical  to rb_convert_type(),  except it  returns ::RUBY_Qnil  instead of
 * raising  exceptions,  in  case  of  conversion  failure.   It  still  raises
 * exceptions  for various  reasons,  like when  the  conversion method  itself
 * raises, though.
 *
 * @param[in]  val            An object to convert.
 * @param[in]  type           A value of enum ::ruby_value_type.
 * @param[in]  name           Name to display on error (e.g. "Array").
 * @param[in]  mid            Conversion method (e.g. "to_ary").
 * @exception  rb_eTypeError  The `mid` does not generate `type`.
 * @retval     RUBY_Qnil      No conversion defined.
 * @retval     otherwise      An object of the specified type.
 */
VALUE rb_check_convert_type(VALUE val, int type, const char *name, const char *mid);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_check_convert_type(), except the  return value type is fixed
 * to ::rb_cInteger.
 *
 * @param[in]  val            An object to convert.
 * @param[in]  mid            Conversion method (e.g. "to_ary").
 * @exception  rb_eTypeError  The `mid` does not generate an integer.
 * @retval     RUBY_Qnil      No conversion defined.
 * @retval     otherwise      An instance of ::rb_cInteger.
 */
VALUE rb_check_to_integer(VALUE val, const char *mid);

/**
 * This is complicated.
 *
 *   - When  the passed  object is  already  an instance  of ::rb_cFloat,  just
 *     returns it as-is.
 *
 *   - When  the passed  object is  something  numeric, the  function tries  to
 *     convert it using `#to_f` method.
 *
 *       - If that conversion fails (this happens for instance when the numeric
 *         is a complex) it returns ::RUBY_Qnil.
 *
 *       - Otherwise returns the conversion result.
 *
 *   - Otherwise it also returns ::RUBY_Qnil.
 *
 * @param[in]  val        An object to convert.
 * @retval     RUBY_Qnil  Conversion from `val` to float is undefined.
 * @retval     otherwise  Converted result.
 */
VALUE rb_check_to_float(VALUE val);

/**
 * Identical  to rb_check_to_int(),  except  it raises  in  case of  conversion
 * mismatch.
 *
 * @param[in]  val            An object to convert.
 * @exception  rb_eTypeError  `#to_int` does not generate an integer.
 * @return     An instance of ::rb_cInteger.
 */
VALUE rb_to_int(VALUE val);

/**
 * Identical to rb_check_to_integer(), except it uses `#to_int` for conversion.
 *
 * @param[in]  val            An object to convert.
 * @exception  rb_eTypeError  `#to_int` does not return an integer.
 * @retval     RUBY_Qnil      No conversion defined.
 * @retval     otherwise      An instance of ::rb_cInteger.
 */
VALUE rb_check_to_int(VALUE val);

/**
 * This  is the  logic behind  `Kernel#Integer`.  Numeric  types are  converted
 * directly,  with  floating  point   numbers  being  truncated.   Strings  are
 * interpreted  strictly; only  leading/trailing whitespaces,  plus/minus sign,
 * radix  indicators  such  as  `0x`,  digits,  and  underscores  are  allowed.
 * Anything else are converted by first trying `#to_int`, then `#to_i`.
 *
 * This is slightly stricter than `String#to_i`.
 *
 * @param[in]  val            An object to convert.
 * @exception  rb_eArgError   Malformed `val` passed.
 * @exception  rb_eTypeError  No conversion defined.
 * @return     An instance of ::rb_cInteger.
 */
VALUE rb_Integer(VALUE val);

/**
 * Identical to rb_check_to_float(), except it raises on error.
 *
 * @param[in]  val            An object to convert.
 * @exception  rb_eTypeError  No conversion defined.
 * @return     An instance of ::rb_cFloat.
 */
VALUE rb_to_float(VALUE val);

/**
 * This  is  the logic  behind  `Kernel#Float`.   Numeric types  are  converted
 * directly  to the  nearest value  that a  Float can  represent.  Strings  are
 * interpreted strictly;  only leading/trailing whitespaces are  allowed except
 * what `strtod` understands.  Anything else are converted using `#to_f`.
 *
 * This is slightly stricter than `String#to_f`.
 *
 * @param[in]  val            An object to convert.
 * @exception  rb_eArgError   Malformed `val` passed.
 * @exception  rb_eTypeError  No conversion defined.
 * @return     An instance of ::rb_cFloat.
 */
VALUE rb_Float(VALUE val);

/**
 * This is the logic behind  `Kernel#String`.  Arguments are converted by first
 * trying `#to_str`, then `#to_s`.
 *
 * @param[in]  val            An object to convert.
 * @exception  rb_eTypeError  No conversion defined.
 * @return     An instance of ::rb_cString.
 */
VALUE rb_String(VALUE val);

/**
 * This is the  logic behind `Kernel#Array`.  Arguments are  converted by first
 * trying `#to_ary`,  then `#to_a`,  and if  both failed,  returns an  array of
 * length 1 that contains the passed argument as the sole contents.
 *
 * @param[in]  val  An object to convert.
 * @return     An instance of ::rb_cArray.
 */
VALUE rb_Array(VALUE val);

/**
 * This is  the logic behind  `Kernel#Hash`.  Arguments are converted  by first
 * trying `#to_hash`.  if it failed, and  the argument is either ::RUBY_Qnil or
 * an empty array, returns an empty hash.  Otherwise an exception is raised.
 *
 * @param[in]  val            An object to convert.
 * @exception  rb_eTypeError  No conversion defined.
 * @return     An instance of ::rb_cHash.
 */
VALUE rb_Hash(VALUE val);

RBIMPL_ATTR_NONNULL(())
/**
 * Converts a textual representation of a  real number into a numeric, which is
 * the nearest value that the return type  can represent, of the value that the
 * argument represents.  This is in fact  a 2-in-1 function whose behaviour can
 * be controlled using  the second (mode) argument.  If the  mode is zero, this
 * function is in "historical"  mode which only understands "floating-constant"
 * defined at ISO/IEC 9899:1990 section 6.1.3.1.  If the mode is nonzero, it is
 * in  "extended"  mode,  which  also  accepts  "hexadecimal-floating-constant"
 * defined at ISO/IEC 9899:2018 section 6.4.4.2.
 *
 * @param[in]  str           A textual representation of a real number.
 * @param[in]  mode          Conversion mode, as described above.
 * @exception  rb_eArgError  Malformed `str` passed.
 * @see        https://bugs.ruby-lang.org/issues/2969
 * @note       Null pointers are allowed, and it returns 0.0 then.
 */
double rb_cstr_to_dbl(const char *str, int mode);

/**
 * Identical to rb_cstr_to_dbl(), except it  accepts a Ruby's string instead of
 * C's.
 *
 * @param[in]  str           A textual representation of a real number.
 * @param[in]  mode          Conversion mode, as described in rb_cstr_to_dbl().
 * @exception  rb_eArgError  Malformed `str` passed.
 * @see        https://bugs.ruby-lang.org/issues/2969
 */
double rb_str_to_dbl(VALUE str, int mode);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_OBJECT_H */
