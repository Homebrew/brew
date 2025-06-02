#ifndef RBIMPL_ITERATOR_H                            /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ITERATOR_H
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
 * @brief      Block related APIs.
 */
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define RB_BLOCK_CALL_FUNC_STRICT 1

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define RUBY_BLOCK_CALL_FUNC_TAKES_BLOCKARG 1

/**
 * Shim for block function parameters.  Historically ::rb_block_call_func_t had
 * only two parameters.  Over time it evolved  to have much more than that.  By
 * using this macro you can absorb such API differences.
 *
 * ```CXX
 * // This works since 2.1.0
 * VALUE my_own_iterator(RB_BLOCK_CALL_FUNC_ARGLIST(y, c));
 * ```
 */
#define RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg) \
    VALUE yielded_arg, VALUE callback_arg, int argc, const VALUE *argv, VALUE blockarg

/**
 * This is the  type of a function that the  interpreter expect for C-backended
 * blocks.  Blocks are  often written in Ruby.  But C  extensions might want to
 * have their own blocks.  In order to  do so authors have to create a separate
 * C function of this type, and pass its pointer to rb_block_call().
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
 *     const auto each = rb_intern("each");
 *     return rb_block_call(self, each, 0, 0, my_own_iterator, self);
 * }
 * ```
 */
typedef VALUE rb_block_call_func(RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg));

/**
 * Shorthand type that represents an iterator-written-in-C function pointer.
 */
typedef rb_block_call_func *rb_block_call_func_t;

/**
 * This is a shorthand of calling `obj.each`.
 *
 * @param[in]  obj  The receiver.
 * @return     What `obj.each` returns.
 *
 * @internal
 *
 * Does anyone still need it?  This API  was to use with rb_iterate(), which is
 * marked deprecated (see below).  Old idiom to call an iterator was:
 *
 * ```CXX
 * VALUE recv;
 * VALUE iter_func(ANYARGS);
 * VALUE iter_data;
 * rb_iterate(rb_each, recv, iter_func, iter_data);
 * ```
 */
VALUE rb_each(VALUE obj);

/**
 * Yields the block.  In Ruby there is  a concept called a block.  You can pass
 * one to a  method.  In a method, when  called with a block, you  can yield it
 * using this function.
 *
 * ```CXX
 * VALUE
 * iterate(VALUE self)
 * {
 *     extern int get_n(VALUE);
 *     extern VALUE get_v(VALUE, VALUE);
 *     const auto n = get_n(self);
 *
 *     for (int i=0; i<n; i++) {
 *         auto v = get_v(self, i);
 *
 *         rb_yield(v);
 *     }
 *     return self;
 * }
 * ```
 *
 * @param[in]  val                 Passed to the block.
 * @exception  rb_eLocalJumpError  There is no block given.
 * @return     Evaluated value of the given block.
 */
VALUE rb_yield(VALUE val);

/**
 * Identical to rb_yield(),  except it takes variadic number  of parameters and
 * pass them to the block.
 *
 * @param[in]  n                   Number of parameters.
 * @param[in]  ...                 List of arguments passed to the block.
 * @exception  rb_eLocalJumpError  There is no block given.
 * @return     Evaluated value of the given block.
 */
VALUE rb_yield_values(int n, ...);

/**
 * Identical to rb_yield_values(),  except it takes the parameters as a C array
 * instead of variadic arguments.
 *
 * @param[in]  n                   Number of parameters.
 * @param[in]  argv                List of arguments passed to the block.
 * @exception  rb_eLocalJumpError  There is no block given.
 * @return     Evaluated value of the given block.
 */
VALUE rb_yield_values2(int n, const VALUE *argv);

/**
 * Identical to  rb_yield_values2(), except you  can specify how to  handle the
 * last element of the given array.
 *
 * @param[in]  n                   Number of parameters.
 * @param[in]  argv                List of arguments passed to the block.
 * @param[in]  kw_splat            Handling of keyword parameters:
 *   - RB_NO_KEYWORDS              `ary`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS            `ary`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS     makes no sense here.
 * @exception  rb_eLocalJumpError  There is no block given.
 * @return     Evaluated value of the given block.
 */
VALUE rb_yield_values_kw(int n, const VALUE *argv, int kw_splat);

/**
 * Identical to  rb_yield_values(), except it  splats an array to  generate the
 * list of parameters.
 *
 * @param[in]  ary                 Array to splat.
 * @exception  rb_eLocalJumpError  There is no block given.
 * @return     Evaluated value of the given block.
 */
VALUE rb_yield_splat(VALUE ary);

/**
 * Identical to rb_yield_splat(), except you can specify how to handle the last
 * element of the given array.
 *
 * @param[in]  ary                 Array to splat.
 * @param[in]  kw_splat            Handling of keyword parameters:
 *   - RB_NO_KEYWORDS              `ary`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS            `ary`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS     makes no sense here.
 * @exception  rb_eLocalJumpError  There is no block given.
 * @return     Evaluated value of the given block.
 */
VALUE rb_yield_splat_kw(VALUE ary, int kw_splat);

/**
 * Pass a passed block.
 *
 * Sometimes you  want to "pass" a  block form one method  to another.  Suppose
 * you have this Ruby method `foo`:
 *
 * ```ruby
 * def foo(x, y)
 *   x.open(y) do |*z|
 *     yield(*z)
 *   end
 * end
 * ```
 *
 * And  suppose you  want  to  translate this  into  C.  Then  rb_yield_block()
 * function is usable in this situation.
 *
 * ```CXX
 * VALUE
 * foo_translated_into_C(VALUE self, VALUE x, VALUE y)
 * {
 *     const auto open = rb_intern("open");
 *
 *     return rb_block_call(x, open, 1, &y, rb_yield_block, Qfalse);
 *     //                                   ^^^^^^^^^^^^^^  Here.
 * }
 * ```
 *
 * @see rb_funcall_passing_block
 *
 * @internal
 *
 * @shyouhei  honestly  doesn't understand  why  this  is needed,  given  there
 * already was rb_funcall_passing_block()  at the time it  was implemented.  If
 * somebody knows its raison d'etre, please improve the document :FIXME:
 */
VALUE rb_yield_block(RB_BLOCK_CALL_FUNC_ARGLIST(yielded_arg, callback_arg)); /* rb_block_call_func */

/**
 * Determines if the current method is given a keyword argument.
 *
 * @retval  false  No keyword argument is given.
 * @retval  true   Keyword argument(s) are given.
 * @ingroup defmethod
 */
int rb_keyword_given_p(void);

/**
 * Determines if the current method is given a block.
 *
 * @retval  false  No block is given.
 * @retval  true   A block is given.
 * @ingroup defmethod
 *
 * @internal
 *
 * This function should have returned a bool.   But at the time it was designed
 * the project was entirely written in K&R C.
 */
int rb_block_given_p(void);

/**
 * Declares that the current method needs a block.
 *
 * @exception  rb_eLocalJumpError  No block given.
 * @ingroup    defmethod
 */
void rb_need_block(void);

#ifndef __cplusplus
RBIMPL_ATTR_DEPRECATED(("by: rb_block_call since 1.9"))
#endif
/**
 * Old way to iterate a block.
 *
 * @deprecated     This is an old API.  Use rb_block_call() instead.
 * @warning        The passed  function must at  least once call a  ruby method
 *                 (to handle interrupts etc.)
 * @param[in]      func1  A function that could yield a value.
 * @param[in,out]  data1  Passed to `func1`
 * @param[in]      proc   A function acts as a block.
 * @param[in,out]  data2  Passed to `proc` as the data2 parameter.
 * @return         What `func1` returns.
 */
VALUE rb_iterate(VALUE (*func1)(VALUE), VALUE data1, rb_block_call_func_t proc, VALUE data2);

#ifdef __cplusplus
namespace ruby {
namespace backward {
/**
 * Old way to iterate a block.
 *
 * @deprecated     This is an old API.  Use rb_block_call() instead.
 * @warning        The passed  function must at  least once call a  ruby method
 *                 (to handle interrupts etc.)
 * @param[in]      iter   A function that could yield a value.
 * @param[in,out]  data1  Passed to `func1`
 * @param[in]      bl     A function acts as a block.
 * @param[in,out]  data2  Passed to `proc` as the data2 parameter.
 * @return         What `func1` returns.
 */
static inline VALUE
rb_iterate_deprecated(VALUE (*iter)(VALUE), VALUE data1, rb_block_call_func_t bl, VALUE data2)
{
    return ::rb_iterate(iter, data1, bl, data2);
}}}

RBIMPL_ATTR_DEPRECATED(("by: rb_block_call since 1.9"))
VALUE rb_iterate(VALUE (*func1)(VALUE), VALUE data1, rb_block_call_func_t proc, VALUE data2);
#endif

/**
 * Identical to  rb_funcallv(), except it  additionally passes a function  as a
 * block.  When the  method yields, `proc` is called with  the yielded value as
 * its first  argument, and  `data2` as  the second.   Yielded values  would be
 * packed into an array if multiple values are yielded at once.
 *
 * @param[in,out]  obj    Receiver.
 * @param[in]      mid    Method signature.
 * @param[in]      argc   Number of arguments.
 * @param[in]      argv   Arguments passed to `obj.mid`.
 * @param[in]      proc   A function acts as a block.
 * @param[in,out]  data2  Passed to `proc` as the data2 parameter.
 * @return         What `obj.mid` returns.
 */
VALUE rb_block_call(VALUE obj, ID mid, int argc, const VALUE *argv, rb_block_call_func_t proc, VALUE data2);

/**
 * Identical to rb_funcallv_kw(), except it additionally passes a function as a
 * block.   It can  also be  seen as  a routine  identical to  rb_block_call(),
 * except it handles keyword-ness of `argv[argc-1]`.
 *
 * @param[in,out]  obj       Receiver.
 * @param[in]      mid       Method signature.
 * @param[in]      argc      Number of arguments including the keywords.
 * @param[in]      argv      Arguments passed to `obj.mid`.
 * @param[in]      proc      A function acts as a block.
 * @param[in,out]  data2     Passed to `proc` as the data2 parameter.
 * @param[in]      kw_splat  Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @return         What `obj.mid` returns.
 */
VALUE rb_block_call_kw(VALUE obj, ID mid, int argc, const VALUE *argv, rb_block_call_func_t proc, VALUE data2, int kw_splat);

/**
 * Identical  to rb_rescue2(),  except it  does not  take a  list of  exception
 * classes.  This is a shorthand of:
 *
 * ```CXX
 * rb_rescue2(b_proc, data1, r_proc, data2, rb_eStandardError, (VALUE)0);
 * ```
 *
 * @param[in]      b_proc  A function which potentially raises an exception.
 * @param[in,out]  data1   Passed to `b_proc`.
 * @param[in]      r_proc  A function which rescues an exception in `b_proc`.
 * @param[in,out]  data2   The first argument of `r_proc`.
 * @return         The return value of `b_proc`  if no exception occurs, or the
 *                 return value of `r_proc` otherwise.
 * @see            rb_rescue
 * @see            rb_ensure
 * @see            rb_protect
 * @ingroup        exception
 */
VALUE rb_rescue(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*r_proc)(VALUE, VALUE), VALUE data2);

/**
 * An equivalent of `rescue` clause.
 *
 * First  it calls  the function  `b_proc` with  `data1` as  the argument.   If
 * nothing is thrown the function happily returns the return value of `b_proc`.
 * When `b_proc` raises an exception, and the exception is a kind of one of the
 * given  exception classes,  it  then  calls `r_proc`  with  `data2` and  that
 * exception.  If the exception does not match any of them, it propagates.
 *
 * @param[in]      b_proc  A function which potentially raises an exception.
 * @param[in,out]  data1   Passed to `b_proc`.
 * @param[in]      r_proc  A function which rescues an exception in `b_proc`.
 * @param[in,out]  data2   The first argument of `r_proc`.
 * @param[in]      ...     1 or  more exception classes.  Must be terminated by
 *                         `(VALUE)0`
 * @return         The return value of `b_proc`  if no exception occurs, or the
 *                 return value of `r_proc` otherwise.
 * @see            rb_rescue
 * @see            rb_ensure
 * @see            rb_protect
 * @ingroup        exception
 */
VALUE rb_rescue2(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*r_proc)(VALUE, VALUE), VALUE data2, ...);

/**
 * Identical to  rb_rescue2(), except  it takes  `va_list` instead  of variadic
 * number  of  arguments.   This  is  exposed to  3rd  parties  because  inline
 * functions use it.  Basically you don't have to bother.
 *
 * @param[in]      b_proc  A function which potentially raises an exception.
 * @param[in,out]  data1   Passed to `b_proc`.
 * @param[in]      r_proc  A function which rescues an exception in `b_proc`.
 * @param[in,out]  data2   The first argument of `r_proc`.
 * @param[in]      ap      1 or  more exception classes.  Must be terminated by
 *                         `(VALUE)0`
 * @return         The return value of `b_proc`  if no exception occurs, or the
 *                 return value of `r_proc` otherwise.
 * @see            rb_rescue
 * @see            rb_ensure
 * @see            rb_protect
 * @ingroup        exception
 */
VALUE rb_vrescue2(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*r_proc)(VALUE, VALUE), VALUE data2, va_list ap);

/**
 * An equivalent to `ensure` clause.   Calls the function `b_proc` with `data1`
 * as the argument, then calls `e_proc` with `data2` when execution terminated.
 *
 * @param[in]      b_proc     A function representing begin clause.
 * @param[in,out]  data1      Passed to `b_proc`.
 * @param[in]      e_proc     A function representing ensure clause.
 * @param[in,out]  data2      Passed to `e_proc`.
 * @retval         RUBY_Qnil  exception occurred inside of `b_proc`.
 * @retval         otherwise  The return value of `b_proc`.
 * @see            rb_rescue
 * @see            rb_rescue2
 * @see            rb_protect
 * @ingroup        exception
 */
VALUE rb_ensure(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*e_proc)(VALUE), VALUE data2);

/**
 * Executes the passed block and catches values thrown from inside of it.
 *
 * In case  the block does  not contain any  throw`, this function  returns the
 * value of the last expression evaluated.
 *
 * ```CXX
 * VALUE
 * iter(RB_BLOCK_CALL_FUNC_ARGLIST(yielded, callback))
 * {
 *     return INT2FIX(123);
 * }
 *
 * VALUE
 * method(VALUE self)
 * {
 *     return rb_catch("tag", iter, Qnil); // returns 123
 * }
 * ```
 *
 * In case there do exist `throw`, Ruby searches up its execution context for a
 * `catch` block.   When a matching catch  is found, the block  stops executing
 * and returns that thrown value instead.
 *
 * ```CXX
 * VALUE
 * iter(RB_BLOCK_CALL_FUNC_ARGLIST(yielded, callback))
 * {
 *     rb_throw("tag", 456);
 *     return INT2FIX(123);
 * }
 *
 * VALUE
 * method(VALUE self)
 * {
 *     return rb_catch("tag", iter, Qnil); // returns 456
 * }
 * ```
 *
 * @param[in]      tag   Arbitrary tag string.
 * @param[in]      func  Function pointer that acts as a block.
 * @param[in,out]  data  Extra parameter passed to `func`.
 * @return         Either caught value for `tag`, or the return value of `func`
 *                 if nothing is thrown.
 */
VALUE rb_catch(const char *tag, rb_block_call_func_t func, VALUE data);

/**
 * Identical to rb_catch(), except it catches arbitrary Ruby objects.
 *
 * @param[in]      tag   Arbitrary tag object.
 * @param[in]      func  Function pointer that acts as a block.
 * @param[in,out]  data  Extra parameter passed to `func`.
 * @return         Either caught value for `tag`, or the return value of `func`
 *                 if nothing is thrown.
 */
VALUE rb_catch_obj(VALUE tag, rb_block_call_func_t func, VALUE data);

RBIMPL_ATTR_NORETURN()
/**
 * Transfers control to the end of  the active `catch` block waiting for `tag`.
 * Raises  rb_eUncughtThrow if  there is  no `catch`  block for  the tag.   The
 * second  parameter supplies  a  return  value for  the  `catch` block,  which
 * otherwise defaults to ::RUBY_Qnil.  For examples, see rb_catch().
 *
 * @param[in]  tag               Tag string.
 * @param[in]  val               Value to throw.
 * @exception  rb_eUncughtThrow  There is no corresponding `catch` clause.
 * @note       It never returns.
 */
void rb_throw(const char *tag, VALUE val);

RBIMPL_ATTR_NORETURN()
/**
 * Identical to rb_throw(), except it allows  arbitrary Ruby object to become a
 * tag.
 *
 * @param[in]  tag               Arbitrary object.
 * @param[in]  val               Value to throw.
 * @exception  rb_eUncughtThrow  There is no corresponding `catch` clause.
 * @note       It never returns.
 */
void rb_throw_obj(VALUE tag, VALUE val);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_ITERATOR_H */
