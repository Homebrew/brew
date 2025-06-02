#ifndef  RBIMPL_INTERN_EVAL_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define  RBIMPL_INTERN_EVAL_H
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
 * @brief      Pre-1.9 era evaluator APIs (now considered miscellaneous).
 */
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* eval.c */
RBIMPL_ATTR_NORETURN()
/**
 * Identical to rb_raise(), except it  raises the passed exception instance as-
 * is instead of creating new one.
 *
 * @param[in]  exc            An instance of a subclass of ::rb_eException.
 * @exception  exc            What is passed.
 * @exception  rb_eTypeError  `exc` is not an exception.
 * @note       It never returns.
 *
 * @internal
 *
 * Wellll  actually, it  can  take more  than what  is  described above.   This
 * function tries  to call `exception`  method of  the passed object.   If that
 * function returns an exception object that is used instead.
 */
void rb_exc_raise(VALUE exc);

RBIMPL_ATTR_NORETURN()
/**
 * Identical to rb_fatal(), except it  raises the passed exception instance as-
 * is instead of creating new one.
 *
 * @param[in]  exc  An instance of a subclass of ::rb_eException.
 * @exception  exc  What is passed.
 * @note       It never returns.
 *
 * @internal
 *
 * You know  what...?  Using this API  you can make arbitrary  exceptions, like
 * `RuntimeError`, that doesn't  interface with `rescue` clause.   This is very
 * confusing.
 */
void rb_exc_fatal(VALUE exc);

/* process.c */

RBIMPL_ATTR_NORETURN()
/**
 * Identical to rb_exit(), except how arguments are passed.
 *
 * @param[in]  argc            Number of objects of `argv`.
 * @param[in]  argv            Contains at most one of the following:
 *                               - ::RUBY_Qtrue - means `EXIT_SUCCESS`.
 *                               - ::RUBY_Qfalse - means `EXIT_FAILURE`.
 *                               - Numerical value - takes that value.
 * @exception  rb_eArgError    Wrong `argc`.
 * @exception  rb_eSystemExit  Exception representing the exit status.
 * @note       It never returns.
 */
VALUE rb_f_exit(int argc, const VALUE *argv);

RBIMPL_ATTR_NORETURN()
/**
 * This is  similar to rb_f_exit().   In fact  on some situation  it internally
 * calls rb_exit().  But can be very esoteric on occasions.
 *
 * It takes up to one argument.  If  an argument is passed, it tries to display
 * that.   Otherwise if  there is  `$!`, displays  that exception  instead.  It
 * finally raise ::rb_eSystemExit in both cases.
 *
 * @param[in]  argc            Number of objects of `argv`.
 * @param[in]  argv            Contains at most one string-ish object.
 * @exception  rb_eArgError    Wrong `argc`.
 * @exception  rb_eTypeError   No conversion from `argv[0]` to String.
 * @exception  rb_eSystemExit  Exception representing `EXIT_FAILURE`.
 * @note       It never returns.
 */
VALUE rb_f_abort(int argc, const VALUE *argv);

/* eval.c*/

RBIMPL_ATTR_NORETURN()
/**
 * Raises an instance of ::rb_eInterrupt.
 *
 * @exception  rb_eInterrupt  Always raises this exception.
 * @note       It never returns.
 */
void rb_interrupt(void);

/**
 * Queries the  name of the  Ruby level method  that is calling  this function.
 * The "name" in this context is the one assigned to the function for the first
 * time (note that methods can have multiple names via aliases).
 *
 * @retval  0          There is no method (e.g. toplevel context).
 * @retval  otherwise  The name of the current method.
 */
ID rb_frame_this_func(void);

RBIMPL_ATTR_NORETURN()
/**
 * This function  is to re-throw  global escapes.  Such global  escapes include
 * exceptions, `throw`, `break`, for example.
 *
 * It makes  sense only  when used  in conjunction  with "protect"  series APIs
 * e.g.  rb_protect(),  rb_load_protect(), rb_eval_string_protect(),  etc.   In
 * case  these functions  experience  global escapes,  they  fill their  opaque
 * `state` return  buffer.  You  can ignore  such escapes.   But if  you decide
 * otherwise, you have to somehow escape globally again.  This function is used
 * for that purpose.
 *
 * @param[in]  state  Opaque state of execution.
 * @note       It never returns.
 *
 * @internal
 *
 * Though  not  a  part  of  our  public  API,  `state`  is  in  fact  an  enum
 * ruby_tag_type.  You can see the potential values by looking at vm_core.h.
 */
void rb_jump_tag(int state);

/**
 * Calls `initialize`  method of the  passed object with the  passed arguments.
 * It also forwards the implicitly passed block to the method.
 *
 * @param[in]  obj            Receiver object.
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           Passed as-is to `obj.initialize`.
 * @exception  rb_eException  Any exceptions happen inside.
 */
void rb_obj_call_init(VALUE obj, int argc, const VALUE *argv);

/**
 * Identical to  rb_obj_call_init(), except you  can specify how to  handle the
 * last element of the given array.
 *
 * @param[in]  obj                Receiver object.
 * @param[in]  argc               Number of objects of `argv`.
 * @param[in]  argv               Passed as-is to `obj.initialize`.
 * @param[in]  kw_splat           Handling of keyword parameters:
 *   - RB_NO_KEYWORDS             `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS           `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS    it depends if there is a passed block.
 * @exception  rb_eNoMethodError  No such method.
 * @exception  rb_eException      Any exceptions happen inside.
 */
void rb_obj_call_init_kw(VALUE, int, const VALUE*, int);

/**
 * Identical to rb_frame_this_func(), except it  returns the named used to call
 * the method.
 *
 * @retval  0          There is no method (e.g. toplevel context).
 * @retval  otherwise  The name of the current method.
 */
ID rb_frame_callee(void);

/**
 * Constructs  an exception  object from  the list  of arguments,  in a  manner
 * similar to Ruby's `raise`.  This function can take:
 *
 *   - No arguments  at all,  i.e. `argc  == 0`.   This is  not a  failure.  It
 *     returns ::RUBY_Qnil then.
 *
 *   - An  object, which  is  an instance  of ::rb_cString.   In  this case  an
 *     instance of  ::rb_eRuntimeError whose  message is  the passed  string is
 *     created then returned.
 *
 *   - An  object, which  responds to  `exception` method,  and optionally  its
 *     argument,  and  optionally  its  backtrace.  For  example  instances  of
 *     subclasses of ::rb_eException  have this method.  What  is returned from
 *     the method is returned.
 *
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           0 up to 3 objects.
 * @exception  rb_eArgError   Wrong `argc`.
 * @exception  rb_eTypeError  `argv[0].exception` returned non-exception.
 * @return     An instance of a subclass of ::rb_eException.
 *
 * @internal
 *
 * Historically  this was  _the_  way  `raise` converted  its  arguments to  an
 * exception.  However they diverged.
 */
VALUE rb_make_exception(int argc, const VALUE *argv);

/* eval_jump.c */

/**
 * Registers a function  that shall run on process  exit.  Registered functions
 * run in  reverse-chronological order,  mixed with  syntactic `END`  block and
 * `Kernel#at_exit`.
 *
 * @param[in]  func  Function to run at process exit.
 * @param[in]  arg   Passed as-is to `func`.
 */
void rb_set_end_proc(void (*func)(VALUE arg), VALUE arg);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_EVAL_H */
