#ifndef RBIMPL_EVAL_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_EVAL_H
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
 * @brief      Declares ::rb_eval_string().
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

RBIMPL_ATTR_NONNULL(())
/**
 * Evaluates the given string in an isolated binding.
 *
 * Here  "isolated"  means  that  the   binding  does  not  inherit  any  other
 * bindings.  This behaves same as the binding for required libraries.
 *
 * `__FILE__`  will  be  `"(eval)"`,  and  `__LINE__`  starts  from  1  in  the
 * evaluation.
 *
 * @param[in]  str            Ruby code to evaluate.
 * @exception  rb_eException  Raises an exception on error.
 * @return     The evaluated result.
 */
VALUE rb_eval_string(const char *str);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to  rb_eval_string(), except  it avoids potential  global escapes.
 * Such global escapes include exceptions, `throw`, `break`, for example.
 *
 * It first evaluates the given string  as rb_eval_string() does.  If no global
 * escape occurred during the evaluation, it returns the result and `*state` is
 * zero.   Otherwise, it  returns some  undefined  value and  sets `*state`  to
 * nonzero.  If state is `NULL`, it is not set in both cases.
 *
 * @param[in]   str    Ruby code to evaluate.
 * @param[out]  state  State of execution.
 * @return      The  evaluated  result  if  succeeded, an  undefined  value  if
 *              otherwise.
 * @post        `*state` is set to zero if succeeded.  Nonzero otherwise.
 * @warning     You have to clear the error info with `rb_set_errinfo(Qnil)` if
 *              you decide to ignore the caught exception.
 * @see         rb_eval_string
 * @see         rb_protect
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
VALUE rb_eval_string_protect(const char *str, int *state);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to rb_eval_string_protect(), except  it evaluates the given string
 * under  a module  binding in  an isolated  binding.  This  is the  same as  a
 * binding for loaded libraries on `rb_load(something, true)`.
 *
 * @param[in]   str    Ruby code to evaluate.
 * @param[out]  state  State of execution.
 * @return      The  evaluated  result  if  succeeded, an  undefined  value  if
 *              otherwise.
 * @post        `*state` is set to zero if succeeded.  Nonzero otherwise.
 * @warning     You have to clear the error info with `rb_set_errinfo(Qnil)` if
 *              you decide to ignore the caught exception.
 * @see         rb_eval_string
 */
VALUE rb_eval_string_wrap(const char *str, int *state);

/**
 * Calls a method.  Can call both public and private methods.
 *
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      n                  Number of arguments that follow.
 * @param[in]      ...                Arbitrary number of method arguments.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 */
VALUE rb_funcall(VALUE recv, ID mid, int n, ...);

/**
 * Identical  to rb_funcall(),  except it  takes the  method arguments  as a  C
 * array.
 *
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      argc               Number of arguments.
 * @param[in]      argv               Arbitrary number of method arguments.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 */
VALUE rb_funcallv(VALUE recv, ID mid, int argc, const VALUE *argv);

/**
 * Identical to  rb_funcallv(), except you can  specify how to handle  the last
 * element of the given array.
 *
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      argc               Number of arguments.
 * @param[in]      argv               Arbitrary number of method arguments.
 * @param[in]      kw_splat           Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 */
VALUE rb_funcallv_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat);

/**
 * Identical  to  rb_funcallv(),  except  it only  takes  public  methods  into
 * account.  This is roughly Ruby's `Object#public_send`.
 *
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      argc               Number of arguments.
 * @param[in]      argv               Arbitrary number of method arguments.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eNoMethodError  The method is private or protected.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 */
VALUE rb_funcallv_public(VALUE recv, ID mid, int argc, const VALUE *argv);

/**
 * Identical to rb_funcallv_public(), except you  can specify how to handle the
 * last element of the given array.  It can also be seen as a routine identical
 * to rb_funcallv_kw(), except it only takes public methods into account.
 *
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      argc               Number of arguments.
 * @param[in]      argv               Arbitrary number of method arguments.
 * @param[in]      kw_splat           Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eNoMethodError  The method is private or protected.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 */
VALUE rb_funcallv_public_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat);

/**
 * @deprecated   This  is an  old  name of  rb_funcallv().   Provided here  for
 *               backwards compatibility  to 2.x programs (introduced  in 2.1).
 *               It is not a good name.  Please don't use it any longer.
 */
#define rb_funcall2 rb_funcallv

/**
 * @deprecated   This is  an old  name of rb_funcallv_public().   Provided here
 *               for  backwards compatibility  to 2.x  programs (introduced  in
 *               2.1).  It is not a good name.  Please don't use it any longer.
 */
#define rb_funcall3 rb_funcallv_public

/**
 * Identical to rb_funcallv_public(), except you can pass the passed block.
 *
 * Sometimes you want  to "pass" a block parameter form  one method to another.
 * Suppose you have this Ruby method `foo`:
 *
 * ```ruby
 * def foo(x, y, &z)
 *   x.open(y, &z)
 * end
 * ```
 *
 * And    suppose   you    want    to   translate    this    into   C.     Then
 * rb_funcall_passing_block() function is usable in this situation.
 *
 * ```CXX
 * VALUE
 * foo_translated_into_C(VALUE self, VALUE x, VALUE y)
 * {
 *     const auto open = rb_intern("open");
 *
 *     return rb_funcall_passing_block(x, open, 1, &y);
 * }
 * ```
 *
 * @see            rb_yield_block
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      argc               Number of arguments.
 * @param[in]      argv               Arbitrary number of method arguments.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eNoMethodError  The method is private or protected.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 */
VALUE rb_funcall_passing_block(VALUE recv, ID mid, int argc, const VALUE *argv);

/**
 * Identical  to rb_funcallv_passing_block(),  except  you can  specify how  to
 * handle  the last  element of  the given  array.  It  can also  be seen  as a
 * routine identical to rb_funcallv_public_kw(), except you can pass the passed
 * block.
 *
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      argc               Number of arguments.
 * @param[in]      argv               Arbitrary number of method arguments.
 * @param[in]      kw_splat           Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eNoMethodError  The method is private or protected.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 */
VALUE rb_funcall_passing_block_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat);

/**
 * Identical to  rb_funcallv_public(), except  you can pass  a block.   A block
 * here  basically is  an  instance of  ::rb_cProc.  If  you  want to  exercise
 * `to_proc` conversion, do so before passing it here.  However nil and symbols
 * are special-case allowed.
 *
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      argc               Number of arguments.
 * @param[in]      argv               Arbitrary number of method arguments.
 * @param[in]      procval            An instance of Proc, Symbol, or NilClass.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eNoMethodError  The method is private or protected.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 *
 * @internal
 *
 * Implementation-wise, `procval`  is in  fact a  "block handler"  object.  You
 * could also pass an IFUNC (block_handler_ifunc) here to say precise.  --- But
 * AFAIK there is no  3rd party way to even know that  there are objects called
 * IFUNC behind-the-scene.
 */
VALUE rb_funcall_with_block(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE procval);

/**
 * Identical to rb_funcallv_with_block(), except you  can specify how to handle
 * the last  element of  the given  array.  It can  also be  seen as  a routine
 * identical to rb_funcallv_public_kw(), except you can pass a block.
 *
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      argc               Number of arguments.
 * @param[in]      argv               Arbitrary number of method arguments.
 * @param[in]      procval            An instance of Proc, Symbol, or NilClass.
 * @param[in]      kw_splat           Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eNoMethodError  The method is private or protected.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 */
VALUE rb_funcall_with_block_kw(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE procval, int kw_splat);

/**
 * This resembles ruby's `super`.
 *
 * @param[in]  argc               Number of arguments.
 * @param[in]  argv               Arbitrary number of method arguments.
 * @exception  rb_eNoMethodError  No super method are there.
 * @exception  rb_eException      Any exceptions happen inside.
 * @return     What the super method evaluates to.
 */
VALUE rb_call_super(int argc, const VALUE *argv);

/**
 * Identical to rb_call_super(), except you can  specify how to handle the last
 * element of the given array.
 *
 * @param[in]  argc               Number of arguments.
 * @param[in]  argv               Arbitrary number of method arguments.
 * @param[in]  kw_splat           Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception  rb_eNoMethodError  No super method are there.
 * @exception  rb_eException      Any exceptions happen inside.
 * @return     What the super method evaluates to.
 */
VALUE rb_call_super_kw(int argc, const VALUE *argv, int kw_splat);

/**
 * This resembles ruby's `self`.
 *
 * @exception  rb_eRuntimeError  Called from outside of method context.
 * @return     Current receiver.
 */
VALUE rb_current_receiver(void);

RBIMPL_ATTR_NONNULL((2))
/**
 * Keyword argument deconstructor.
 *
 * Retrieves argument values bound to  keywords, which directed by `table` into
 * `values`,  deleting retrieved  entries  from `keyword_hash`  along the  way.
 * First  `required` number  of  IDs  referred by  `table`  are mandatory,  and
 * succeeding `optional`  (`-optional-1` if  `optional` is negative)  number of
 * IDs are  optional.  If a mandatory  key is not contained  in `keyword_hash`,
 * raises ::rb_eArgError.  If an optional key is not present in `keyword_hash`,
 * the  corresponding  element  in  `values`   is  set  to  ::RUBY_Qundef.   If
 * `optional` is negative, rest of `keyword_hash` are ignored, otherwise raises
 * ::rb_eArgError.
 *
 * @warning     Handling keyword arguments in the  C API is less efficient than
 *              handling them  in Ruby.  Consider  using a Ruby  wrapper method
 *              around a non-keyword C function.
 * @see         https://bugs.ruby-lang.org/issues/11339
 * @param[out]  keyword_hash  Target hash to deconstruct.
 * @param[in]   table         List of keywords that you are interested in.
 * @param[in]   required      Number of mandatory keywords.
 * @param[in]   optional      Number of optional keywords (can be negative).
 * @param[out]  values        Buffer to be filled.
 * @exception   rb_eArgError  Absence of a mandatory keyword.
 * @exception   rb_eArgError  Found an unknown keyword.
 * @return      Number of found values that are stored into `values`.
 */
int rb_get_kwargs(VALUE keyword_hash, const ID *table, int required, int optional, VALUE *values);

RBIMPL_ATTR_NONNULL(())
/**
 * Splits a hash into two.
 *
 * Takes  a hash  of various  keys, and  split it  into symbol-keyed  parts and
 * others.   Symbol-keyed part  becomes  the return  value.   What remains  are
 * returned as a new hash object stored at the argument pointer.
 *
 * @param[in,out]  orighash  Pointer to a target hash to split.
 * @return         An extracted keyword hash.
 * @post           Upon  successful return  `orighash` points  to another  hash
 *                 object, whose contents are the remainder of the operation.
 * @note           The argument hash object is not modified.
 */
VALUE rb_extract_keywords(VALUE *orighash);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_EVAL_H */
