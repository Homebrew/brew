#ifndef RBIMPL_INTERN_VM_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_VM_H
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
 * @brief      Public APIs related to rb_cRubyVM.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* vm.c */

/**
 * Resembles `__LINE__`.
 *
 * @retval  0          Current execution context not in a ruby method.
 * @retval  otherwise  The current  line number  of the  current thread  of the
 *                     current ractor of the current execution context.
 */
int rb_sourceline(void);

/**
 * Resembles `__FILE__`.
 *
 * @retval  0          Current execution context not in a ruby method.
 * @retval  otherwise  The current  source path  of the  current thread  of the
 *                     current ractor of the current execution context.
 * @note    This may or may not be an absolute path.
 */
const char *rb_sourcefile(void);

/**
 * Resembles `__method__`.
 *
 * @param[out]  idp     Return buffer for method id.
 * @param[out]  klassp  Return buffer for class.
 * @retval      0       Current execution context not in a method.
 * @retval      1       Successful return.
 * @post        Upon successful return `*idp` and `*klassp` are updated to have
 *              the current method name and its defined class respectively.
 * @note        Both parameters can be `NULL`.
 */
int rb_frame_method_id_and_class(ID *idp, VALUE *klassp);

/* vm_eval.c */

/**
 * Identical  to  rb_funcallv(), except  it  returns  ::RUBY_Qundef instead  of
 * raising ::rb_eNoMethodError.
 *
 * @param[in,out]  recv         Receiver of the method.
 * @param[in]      mid          Name of the method to call.
 * @param[in]      argc         Number of arguments.
 * @param[in]      argv         Arbitrary number of method arguments.
 * @retval         RUBY_Qundef  `recv` doesn't respond to `mid`.
 * @retval         otherwise    What the method evaluates to.
 */
VALUE rb_check_funcall(VALUE recv, ID mid, int argc, const VALUE *argv);

/**
 * Identical to  rb_check_funcall(), except you  can specify how to  handle the
 * last element of the given array.  It can also be seen as a routine identical
 * to  rb_funcallv_kw(), except  it  returns ::RUBY_Qundef  instead of  raising
 * ::rb_eNoMethodError.
 *
 * @param[in,out]  recv         Receiver of the method.
 * @param[in]      mid          Name of the method to call.
 * @param[in]      argc         Number of arguments.
 * @param[in]      argv         Arbitrary number of method arguments.
 * @param[in]      kw_splat     Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @retval         RUBY_Qundef  `recv` doesn't respond to `mid`.
 * @retval         otherwise    What the method evaluates to.
 */
VALUE rb_check_funcall_kw(VALUE recv, ID mid, int argc, const VALUE *argv, int kw_splat);

/**
 * This API  is practically a  variant of rb_proc_call_kw()  now.  Historically
 * when there  still was a  concept called `$SAFE`, this  was an API  for that.
 * But we  no longer have  that.  This function  basically ended its  role.  It
 * just remains here because of no harm.
 *
 * @param[in]  cmd       A string, or something callable.
 * @param[in]  arg       Argument passed to the call.
 * @param[in]  kw_splat  Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `arg`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `arg`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @return     What the command evaluates to.
 */
VALUE rb_eval_cmd_kw(VALUE cmd, VALUE arg, int kw_splat);

/**
 * Identical to rb_funcallv(), except it takes Ruby's array instead of C's.
 * @param[in,out]  recv               Receiver of the method.
 * @param[in]      mid                Name of the method to call.
 * @param[in]      args               An instance of ::RArray.
 * @exception      rb_eNoMethodError  No such method.
 * @exception      rb_eException      Any exceptions happen inside.
 * @return         What the method evaluates to.
 * @pre            `args` must  be an ::RArray.  Call  `to_ary` beforehand when
 *                 necessary.
 */
VALUE rb_apply(VALUE recv, ID mid, VALUE args);

/**
 * Evaluates a string  containing Ruby source code, or the  given block, within
 * the  context of  the receiver.  In order  to set  the context,  the variable
 * `self` is set to `recv` while the  code is executing, giving the code access
 * to `recv`'s instance variables and private methods.
 *
 * When given a block, `recv` is also passed in as the block's only argument.
 *
 * When  given a  string, the  optional second  and third  parameters supply  a
 * filename and starting  line number that are used  when reporting compilation
 * errors.
 *
 * @param[in]  argc  Number of objects in `argv`
 * @param[in]  argv  C array of 0 up to 3 elements.
 * @param[in]  recv  The object in question.
 * @return     What was evaluated.
 */
VALUE rb_obj_instance_eval(int argc, const VALUE *argv, VALUE recv);

/**
 * Executes the  given block within the  context of the receiver.   In order to
 * set the  context, the  variable `self` is  set to `recv`  while the  code is
 * executing, giving the code access to `recv`'s instance variables.  Arguments
 * are passed as block parameters.
 *
 * @param[in]  argc  Number of objects in `argv`
 * @param[in]  argv  Arbitrary parameters to be passed to the block.
 * @param[in]  recv  The object in question.
 * @return     What was evaluated.
 * @note       Don't  confuse   this  with  rb_obj_instance_eval().    The  key
 *             difference is whether  you can pass arbitrary  parameters to the
 *             block, like this:
 *
 * ```ruby
 * class Foo
 *   def initialize
 *     @foo = 5
 *   end
 * end
 * Foo.new.instance_exec(7) {|i| @foo + i } # => 12
 * ```
 */
VALUE rb_obj_instance_exec(int argc, const VALUE *argv, VALUE recv);

/**
 * Identical to rb_obj_instance_eval(), except  it evaluates within the context
 * of module.
 *
 * @param[in]  argc  Number of objects in `argv`
 * @param[in]  argv  C array of 0 up to 3 elements.
 * @param[in]  mod   The module in question.
 * @pre        `mod` must be a Module.
 * @return     What was evaluated.
 */
VALUE rb_mod_module_eval(int argc, const VALUE *argv, VALUE mod);

/**
 * Identical to rb_obj_instance_exec(), except  it evaluates within the context
 * of module.
 *
 * @param[in]  argc  Number of objects in `argv`
 * @param[in]  argv  Arbitrary parameters to be passed to the block.
 * @param[in]  mod   The module in question.
 * @pre        `mod` must be a Module.
 * @return     What was evaluated.
 */
VALUE rb_mod_module_exec(int argc, const VALUE *argv, VALUE mod);

/* vm_method.c */

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define HAVE_RB_DEFINE_ALLOC_FUNC 1

/**
 * This is  the type of  functions that ruby calls  when trying to  allocate an
 * object.  It is  sometimes necessary to allocate extra memory  regions for an
 * object.  When you define a class that uses ::RTypedData, it is typically the
 * case.  On  such situations  define a function  of this type  and pass  it to
 * rb_define_alloc_func().
 *
 * @param[in]  klass  The class that this function is registered.
 * @return     A newly allocated instance of `klass`.
 */
typedef VALUE (*rb_alloc_func_t)(VALUE klass);

/**
 * Sets the allocator function of a class.
 *
 * @param[out]  klass  The class to modify.
 * @param[in]   func   An allocator function for the class.
 * @pre         `klass` must be an instance of Class.
 */
void rb_define_alloc_func(VALUE klass, rb_alloc_func_t func);

/**
 * Deletes the  allocator function of  a class.   It is sometimes  desirable to
 * restrict creation  of an instance of  a class.  For example  it rarely makes
 * sense for  a DB adaptor class  to allow programmers creating  DB row objects
 * without querying  the DB  itself.  You  can kill  sporadic creation  of such
 * objects then,  by nullifying  the allocator function  using this  API.  Your
 * object shall be allocated using #RB_NEWOBJ_OF() directly.
 *
 * @param[out]  klass  The class to modify.
 * @pre         `klass` must be an instance of Class.
 */
void rb_undef_alloc_func(VALUE klass);

/**
 * Queries the allocator function of a class.
 *
 * @param[in]  klass      The class in question.
 * @pre        `klass` must be an instance of Class.
 * @retval     0          No allocator function is registered.
 * @retval     otherwise  The allocator function.
 *
 * @internal
 *
 * Who cares?  @shyouhei fins no practical usage of the return value.  Maybe we
 * need KonMari.
 */
rb_alloc_func_t rb_get_alloc_func(VALUE klass);

/**
 * Clears  the constant  cache.   Extension libraries  should  not bother  such
 * things.   Just forget  about this  API (or  even, the  presence of  constant
 * cache).
 *
 * @internal
 *
 * Completely no idea why this function is defined in vm_method.c.
 */
void rb_clear_constant_cache(void);

/**
 * Resembles `alias`.
 *
 * @param[out]  klass            Where to define an alias.
 * @param[in]   dst              New name.
 * @param[in]   src              Existing name.
 * @exception   rb_eTypeError    `klass` is not a class.
 * @exception   rb_eFrozenError  `klass` is frozen.
 * @exception   rb_eNameError    No such method named `src`.
 * @post        `klass` has a method named `dst`, which is the identical to its
 *              method named `src`.
 */
void rb_alias(VALUE klass, ID dst, ID src);

/**
 * This function resembles now-deprecated `Module#attr`.
 *
 * @param[out]  klass              Where to define an attribute.
 * @param[in]   name               Name of an instance variable.
 * @param[in]   need_reader        Whether attr_reader is needed.
 * @param[in]   need_writer        Whether attr_writer is needed.
 * @param[in]   honour_visibility  Whether to use the current visibility.
 * @exception   rb_eTypeError      `klass` is not a class.
 * @exception   rb_eFrozenError    `klass` is frozen.
 * @post        If `need_reader` is set `klass` has a method named `name`.
 * @post        If `need_writer` is set `klass` has a method named `name=`.
 *
 * @internal
 *
 * The three `int` arguments should have been bool, but there was no such thing
 * like a bool when K&R was used in this project.
 */
void rb_attr(VALUE klass, ID name, int need_reader, int need_writer, int honour_visibility);

RBIMPL_ATTR_NONNULL(())
/**
 * Removes a  method.  Don't confuse  this to rb_undef_method(),  which doesn't
 * remove a method.  This one resembles `Module#remove_method`.
 *
 * @param[out]  klass            The class to remove a method.
 * @param[in]   name             Name of a method to be removed.
 * @exception   rb_eTypeError    `klass` is a non-module.
 * @exception   rb_eFrozenError  `klass` is frozen.
 * @exception   rb_eNameError    No such method.
 * @see         rb_undef_method
 */
void rb_remove_method(VALUE klass, const char *name);

/**
 * Identical to rb_remove_method(), except it accepts the method name as ::ID.
 *
 * @param[out]  klass            The class to remove a method.
 * @param[in]   mid              Name of a method to be removed.
 * @exception   rb_eTypeError    `klass` is a non-module.
 * @exception   rb_eFrozenError  `klass` is frozen.
 * @exception   rb_eNameError    No such method.
 * @see         rb_undef
 */
void rb_remove_method_id(VALUE klass, ID mid);

/**
 * Queries if the  klass has this method.   This function has only  one line of
 * document in the implementation that states "// deprecated".  Don't know what
 * that means though.
 *
 * @param[in]  klass  The class in question.
 * @param[in]  id     The method name to query.
 * @param[in]  ex     Undocumented magic value.
 * @retval     false  Method not found.
 * @retval     true   There is a method.
 * @pre        `klass` must be a module.
 *
 * @internal
 *
 * @shyouhei has no  motivation to describe what should be  passed to `ex`.  It
 * seems this function should just be trashed.
 */
int rb_method_boundp(VALUE klass, ID id, int ex);

/**
 * Well...  Let us hesitate from describing what a "basic definition" is.  This
 * nuanced concept  should have been  kept private.  Just please.   Don't touch
 * it.  This function is a badly distributed random number generator.  Right?
 *
 * @param[in]  klass  The class in question.
 * @param[in]  mid    The method name in question.
 * @retval     1      It is.
 * @retval     0      It isn't.
 */
int rb_method_basic_definition_p(VALUE klass, ID mid);

/**
 * Identical to  rb_respond_to(), except  it additionally takes  the visibility
 * parameter.   This   does  not   make  difference   unless  the   object  has
 * `respond_to?` undefined,  but has `respond_to_missing?` defined.   That case
 * the passed argument becomes the second argument of `respond_to_missing?`.
 *
 * @param[in]  obj        The object in question.
 * @param[in]  mid        The method name in question.
 * @param[in]  private_p  This    is   the    second   argument    of   `obj`'s
 *                        `respond_to_missing?`.
 * @retval     1          Yes it does.
 * @retval     0          No it doesn't.
 */
int rb_obj_respond_to(VALUE obj, ID mid, int private_p);

/**
 * Queries if  the object responds  to the  method.  This involves  calling the
 * object's `respond_to?` method.
 *
 * @param[in]  obj        The object in question.
 * @param[in]  mid        The method name in question.
 * @retval     1          Yes it does.
 * @retval     0          No it doesn't.
 */
int rb_respond_to(VALUE obj, ID mid);

RBIMPL_ATTR_NORETURN()
/**
 * Raises  ::rb_eNotImpError.   This  function  is   used  as  an  argument  to
 * rb_define_method() etc.
 *
 * ```CXX
 * rb_define_method(rb_cFoo, "foo", rb_f_notimplement, -1);
 * ```
 *
 * @param     argc             Unused parameter.
 * @param     argv             Unused parameter.
 * @param     obj              Unused parameter.
 * @param     marker           Unused parameter.
 * @exception rb_eNotImpError  Always.
 * @return    Never returns.
 *
 * @internal
 *
 * See also the Q&A section of include/ruby/internal/anyargs.h.
 */
VALUE rb_f_notimplement(int argc, const VALUE *argv, VALUE obj, VALUE marker);
#if !defined(RUBY_EXPORT) && defined(_WIN32)
RUBY_EXTERN VALUE (*const rb_f_notimplement_)(int, const VALUE *, VALUE, VALUE marker);
#define rb_f_notimplement (*rb_f_notimplement_)
#endif

/* vm_backtrace.c */

/**
 * Prints the backtrace  out to the standard error.  This  just confuses people
 * for no reason.  Evil souls must only use it.
 *
 * @internal
 *
 * Actually it is very useful when called from an interactive GDB session.
 */
void rb_backtrace(void);

/**
 * Creates the good old fashioned array-of-strings style backtrace info.
 *
 * @return  An   array  which   contains   strings,  which   are  the   textual
 *          representations of the backtrace locations of the current thread of
 *          the current ractor of the current execution context.
 * @note    Ruby      scripts      can      access      more      sophisticated
 *          `Thread::Backtrace::Location`.  But it seems there  is no way for C
 *          extensions to use that API.
 */
VALUE rb_make_backtrace(void);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_VM_H */
