#ifndef RBIMPL_INTERN_PROC_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_PROC_H
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
 * @brief      Public APIs related to ::rb_cProc.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/iterator.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* proc.c */

/**
 * Constructs a  Proc object  from implicitly passed  components.  When  a ruby
 * method is  called with a block,  that block is not  explicitly passed around
 * using C level function parameters.   This function gathers all the necessary
 * info to turn them into a Ruby level instance of ::rb_cProc.
 *
 * @exception  rb_eArgError  There is no passed block.
 * @return     An instance of ::rb_cProc.
 */
VALUE rb_block_proc(void);

/**
 * Identical to rb_proc_new(), except it returns a lambda.
 *
 * @exception  rb_eArgError  There is no passed block.
 * @return     An instance of ::rb_cProc.
 */
VALUE rb_block_lambda(void);

/**
 * This is an rb_iterate() + rb_block_proc() combo.
 *
 * ```CXX
 * VALUE
 * my_own_iterator(RB_BLOCK_CALL_FUNC_ARGLIST(y, c))
 * {
 *     const auto plus = rb_intern("+");
 *     return rb_funcall(c, plus, 1, y);
 * }
 *
 * VALUE
 * my_own_method(VALUE self)
 * {
 *     return rb_proc_new(my_own_iterator, self);
 * }
 * ```
 *
 * @param[in]  func          A backend function of a proc.
 * @param[in]  callback_arg  Passed to `func`'s callback_arg.
 * @return     A C-backended proc object.
 *
 */
VALUE rb_proc_new(rb_block_call_func_t func, VALUE callback_arg);

/**
 * Queries if the given object is a proc.
 *
 * @note       This is about the object's data structure, not its class etc.
 * @param[in]  recv         Object in question.
 * @retval     RUBY_Qtrue   It is a proc.
 * @retval     RUBY_Qfalse  Otherwise.
 */
VALUE rb_obj_is_proc(VALUE recv);

/**
 * Evaluates the passed proc with the passed arguments.
 *
 * @param[in]  recv           The proc to call.
 * @param[in]  args           An instance of ::RArray which is the arguments.
 * @exception  rb_eException  Any exceptions happen inside.
 * @return     What the proc evaluates to.
 */
VALUE rb_proc_call(VALUE recv, VALUE args);

/**
 * Identical to rb_proc_call(),  except you can specify how to  handle the last
 * element of the given array.
 *
 * @param[in]  recv             The proc to call.
 * @param[in]  args             An instance of ::RArray which is the arguments.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `args`' last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `args`' last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception  rb_eException    Any exceptions happen inside.
 * @return     What the proc evaluates to.
 */
VALUE rb_proc_call_kw(VALUE recv, VALUE args, int kw_splat);

/**
 * Identical to rb_proc_call(),  except you can additionally  pass another proc
 * object, as a block.  Nowadays procs can take blocks:
 *
 * ```ruby
 * l = -> (positional, optional=nil, *rest, kwarg:, **kwrest, &block) {
 *   #                   ... how can we pass this `&block`?   ^^^^^^
 * }
 * ```
 *
 * And this function is to pass one to such procs.
 *
 * @param[in]  recv           The proc to call.
 * @param[in]  argc           Number of arguments.
 * @param[in]  argv           Arbitrary number of proc arguments.
 * @param[in]  proc           Proc as a passed block.
 * @exception  rb_eException  Any exceptions happen inside.
 * @return     What the proc evaluates to.
 */
VALUE rb_proc_call_with_block(VALUE recv, int argc, const VALUE *argv, VALUE proc);

/**
 * Identical to rb_proc_call_with_block(), except you can specify how to handle
 * the last  element of  the given  array.  It can  also be  seen as  a routine
 * identical  to rb_proc_call_kw(),  except you  can additionally  pass another
 * proc object as a block.
 *
 * @param[in]  recv             The proc to call.
 * @param[in]  argc             Number of arguments.
 * @param[in]  argv             Arbitrary number of proc arguments.
 * @param[in]  proc             Proc as a passed block.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `args`' last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `args`' last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception  rb_eException    Any exceptions happen inside.
 * @return     What the proc evaluates to.
 */
VALUE rb_proc_call_with_block_kw(VALUE recv, int argc, const VALUE *argv, VALUE proc, int kw_splat);

/**
 * Queries the number  of mandatory arguments of the given  Proc.  If its block
 * is declared  to take no  arguments, returns `0`.  If  the block is  known to
 * take  exactly  `n`  arguments,  returns  `n`.  If  the  block  has  optional
 * arguments, returns `-n-1`,  where `n` is the number  of mandatory arguments,
 * with the exception  for blocks that are  not lambdas and have  only a finite
 * number of  optional arguments;  in this latter  case, returns  `n`.  Keyword
 * arguments will be considered as  a single additional argument, that argument
 * being mandatory if any keyword argument is mandatory.
 *
 * @param[in]  recv  Target Proc object.
 * @retval     0     It takes no arguments.
 * @retval     >0    It takes exactly this number of arguments.
 * @retval     <0    It takes optional arguments.
 */
int rb_proc_arity(VALUE recv);

/**
 * Queries if the given object is a lambda.  Instances of ::rb_cProc are either
 * lambda  or  proc.   They  differ  in  several  points.   This  function  can
 * distinguish them without actually evaluating their contents.
 *
 * @param[in]  recv         Target proc object.
 * @retval     RUBY_Qtrue   It is a lambda.
 * @retval     RUBY_Qfalse  Otherwise.
 */
VALUE rb_proc_lambda_p(VALUE recv);

/**
 * Snapshots the  current execution  context and  turn it  into an  instance of
 * ::rb_cBinding.
 *
 * @return  An instance of ::rb_cBinding.
 */
VALUE rb_binding_new(void);

/**
 * Creates a method object.  A method object is a proc-like object that you can
 * "call".  Note  that a  method object  snapshots the method  at the  time the
 * object is created:
 *
 * ```ruby
 * class Foo
 *   def foo
 *     return 1
 *   end
 * end
 *
 * obj = Foo.new.method(:foo)
 *
 * class Foo
 *   def foo
 *     return 2
 *   end
 * end
 *
 * obj.call # => 1, not 2.
 * ```
 *
 * @param[in]  recv               Receiver of the method.
 * @param[in]  mid                Method name, in either String or Symbol.
 * @exception  rb_eNoMethodError  No such method.
 * @return     An instance of ::rb_cMethod.
 */
VALUE rb_obj_method(VALUE recv, VALUE mid);

/**
 * Queries if the given object is a method.
 *
 * @note       This is about the object's data structure, not its class etc.
 * @param[in]  recv         Object in question.
 * @retval     RUBY_Qtrue   It is a method.
 * @retval     RUBY_Qfalse  Otherwise.
 */
VALUE rb_obj_is_method(VALUE recv);

/**
 * Evaluates the passed method with the passed arguments.
 *
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           Arbitrary number of method arguments.
 * @param[in]  recv           The method object to call.
 * @exception  rb_eTypeError  `recv` is not a method.
 * @exception  rb_eException  Any exceptions happen inside.
 * @return     What the method returns.
 */
VALUE rb_method_call(int argc, const VALUE *argv, VALUE recv);

/**
 * Identical to rb_method_call(), except you can specify how to handle the last
 * element of the given array.
 *
 * @param[in]  argc             Number of objects of `argv`.
 * @param[in]  argv             Arbitrary number of method arguments.
 * @param[in]  recv             The method object to call.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `args`' last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `args`' last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception  rb_eTypeError    `recv` is not a method.
 * @exception  rb_eException    Any exceptions happen inside.
 * @return     What the method returns.
 */
VALUE rb_method_call_kw(int argc, const VALUE *argv, VALUE recv, int kw_splat);

/**
 * Identical to  rb_proc_call(), except you can  additionally pass a proc  as a
 * block.
 *
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           Arbitrary number of method arguments.
 * @param[in]  recv           The method object to call.
 * @param[in]  proc           Proc as a passed block.
 * @exception  rb_eTypeError  `recv` is not a method.
 * @exception  rb_eException  Any exceptions happen inside.
 * @return     What the method returns.
 */
VALUE rb_method_call_with_block(int argc, const VALUE *argv, VALUE recv, VALUE proc);

/**
 * Identical  to rb_method_call_with_block(),  except  you can  specify how  to
 * handle  the last  element of  the given  array.  It  can also  be seen  as a
 * routine identical  to rb_method_call_kw(), except you  can additionally pass
 * another proc object as a block.
 *
 * @param[in]  argc             Number of objects of `argv`.
 * @param[in]  argv             Arbitrary number of method arguments.
 * @param[in]  recv             The method object to call.
 * @param[in]  proc             Proc as a passed block.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `args`' last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `args`' last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception  rb_eTypeError    `recv` is not a method.
 * @exception  rb_eException    Any exceptions happen inside.
 * @return     What the method returns.
 */
VALUE rb_method_call_with_block_kw(int argc, const VALUE *argv, VALUE recv, VALUE proc, int kw_splat);

/**
 * Queries the number of mandatory arguments of the method defined in the given
 * module.  If it is  declared to take no arguments, returns  `0`.  If it takes
 * exactly `n` arguments,  returns `n`.  If it has  optional arguments, returns
 * `-n-1`, where `n`  is the number of mandatory  arguments.  Keyword arguments
 * will  be considered  as a  single additional  argument, that  argument being
 * mandatory if any keyword argument is mandatory.
 *
 * @param[in]  mod   Namespace to search a method for.
 * @param[in]  mid   Method id.
 * @retval     0     It takes no arguments.
 * @retval     >0    It takes exactly this number of arguments.
 * @retval     <0    It takes optional arguments.
 */
int rb_mod_method_arity(VALUE mod, ID mid);

/**
 * Identical to rb_mod_method_arity(), except it searches for singleton methods
 * rather than instance methods.
 *
 * @param[in]  obj   Object to search for a singleton method.
 * @param[in]  mid   Method id.
 * @retval     0     It takes no arguments.
 * @retval     >0    It takes exactly this number of arguments.
 * @retval     <0    It takes optional arguments.
 */
int rb_obj_method_arity(VALUE obj, ID mid);

/* eval.c */

RBIMPL_ATTR_NONNULL((1))
/**
 * Protects a  function call from  potential global escapes from  the function.
 * Such global escapes include exceptions, `throw`, `break`, for example.
 *
 * It first calls the function func with  `args` as the argument.  If no global
 * escape occurred during  the function, it returns the result  and `*state` is
 * zero.  Otherwise, it  returns ::RUBY_Qnil and sets `*state`  to nonzero.  If
 * `state` is `NULL`, it is not set in both cases.
 *
 * @param[in]   func   A function that potentially escapes globally.
 * @param[in]   args   Passed as-is to `func`.
 * @param[out]  state  State of execution.
 * @return      What  `func` returns,  or an  undefined value  when it  did not
 *              return.
 * @post        `*state` is set to zero if succeeded.  Nonzero otherwise.
 * @warning     You have to clear the error info with `rb_set_errinfo(Qnil)` if
 *              you decide to ignore the caught exception.
 * @see         rb_eval_string_protect()
 * @see         rb_load_protect()
 *
 * @internal
 *
 * The "undefined value"  described above is in fact ::RUBY_Qnil  for now.  But
 * @shyouhei doesn't think that we would never change that.
 *
 * Though   not  a   part  of   our  public   API,  `state`   is  in   fact  an
 * enum ruby_tag_type.  You can  see the potential "nonzero"  values by looking
 * at vm_core.h.
 */
VALUE rb_protect(VALUE (*func)(VALUE args), VALUE args, int *state);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_PROC_H */
