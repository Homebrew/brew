#ifndef  RBIMPL_INTERN_CONT_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define  RBIMPL_INTERN_CONT_H
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
 * @brief      Public APIs related to rb_cFiber.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/iterator.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* cont.c */

/**
 * Creates a Fiber instance from a C-backended block.
 *
 * @param[in]  func          A function, to become the fiber's body.
 * @param[in]  callback_obj  Passed as-is to `func`.
 * @return     An allocated  new instance  of rb_cFiber, which  is ready  to be
 *             "resume"d.
 */
VALUE rb_fiber_new(rb_block_call_func_t func, VALUE callback_obj);

/**
 * Creates a Fiber instance from a C-backended block with the specified
 * storage.
 *
 * If the given storage is Qundef or Qtrue, this function is equivalent to
 * rb_fiber_new() which inherits storage from the current fiber.
 *
 * Specifying Qtrue is experimental and may be changed in the future.
 *
 * If the given storage is Qnil, this function will lazy initialize the
 * internal storage which starts of empty (without any inheritance).
 *
 * Otherwise, the given storage is used as the internal storage.
 *
 * @param[in]  func          A function, to become the fiber's body.
 * @param[in]  callback_obj  Passed as-is to `func`.
 * @param[in]  storage       The way to set up the storage for the fiber.
 * @return     An allocated  new instance  of rb_cFiber, which  is ready  to be
 *             "resume"d.
 */
VALUE rb_fiber_new_storage(rb_block_call_func_t func, VALUE callback_obj, VALUE storage);

/**
 * Queries  the fiber  which  is  calling this  function.   Any ruby  execution
 * context has its fiber, either explicitly or implicitly.
 *
 * @return  The current fiber.
 */
VALUE rb_fiber_current(void);

/**
 * Queries the  liveness of the  passed fiber.   "Alive" in this  context means
 * that  the fiber  can  still be  resumed.   Once  it reaches  is  its end  of
 * execution, this function returns ::RUBY_Qfalse.
 *
 * @param[in]  fiber        A target fiber.
 * @retval     RUBY_Qtrue   It is.
 * @retval     RUBY_Qfalse  It isn't.
 */
VALUE rb_fiber_alive_p(VALUE fiber);

/**
 * Queries if an object is a fiber.
 *
 * @param[in]  obj          Arbitrary ruby object.
 * @retval     RUBY_Qtrue   It is.
 * @retval     RUBY_Qfalse  It isn't.
 */
VALUE rb_obj_is_fiber(VALUE obj);

/**
 * Resumes the  execution of the passed  fiber, either from the  point at which
 * the last  rb_fiber_yield() was  called if  any, or at  the beginning  of the
 * fiber body if it is the first call to this function.
 *
 * Other arguments are passed into the fiber's body, either as return values of
 * rb_fiber_yield() in case it switches to  there, or as the block parameter of
 * the fiber body if it switches to the beginning of the fiber.
 *
 * The return  value of this  function is either  the value passed  to previous
 * rb_fiber_yield() call, or  the ultimate evaluated value of  the entire fiber
 * body if the execution reaches the end of it.
 *
 * When an exception happens inside of a fiber it propagates to this function.
 *
 * ```ruby
 * f = Fiber.new do |i|
 *   puts "<x> =>> #{i}"
 *   puts "<y> <-- #{i + 1}"
 *   j = Fiber.yield(i + 1)
 *   puts "<z> =>> #{j}"
 *   puts "<w> <-- #{j + 1}"
 *   next j + 1
 * end
 *
 * puts "[a] <-- 1"
 * p = f.resume(1)
 * puts "[b] =>> #{p}"
 * puts "[c] <-- #{p + 1}"
 * q = f.resume(p + 1)
 * puts "[d] =>> #{q}"
 * ```
 *
 * Above program executes in `[a] <x> <y> [b] [c] <z> <w> [d]`.
 *
 * @param[out]  fiber          The fiber to resume.
 * @param[in]   argc            Number of objects of `argv`.
 * @param[in]   argv            Passed (somehow) to `fiber`.
 * @exception   rb_eFiberError  `fib` is terminated etc.
 * @exception   rb_eException   Any exceptions happen in `fiber`.
 * @return      (See above)
 * @note        This function _does_ return.
 *
 * @internal
 *
 * @shyouhei  expected  this function  to  raise  ::rb_eFrozenError for  frozen
 * fibers but it doesn't in practice.  Intentional or ...?
 */
VALUE rb_fiber_resume(VALUE fiber, int argc, const VALUE *argv);

/**
 * Identical to  rb_fiber_resume(), except  you can specify  how to  handle the
 * last element of the given array.
 *
 * @param[out]  fiber           The fiber to resume.
 * @param[in]   argc            Number of objects of `argv`.
 * @param[in]   argv            Passed (somehow) to `fiber`.
 * @param[in]   kw_splat        Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception   rb_eFiberError  `fiber` is terminated etc.
 * @exception   rb_eException   Any exceptions happen in `fiber`.
 * @return      Either what was yielded or the last value of the fiber body.
 */
VALUE rb_fiber_resume_kw(VALUE fiber, int argc, const VALUE *argv, int kw_splat);

/**
 * Yields the  control back to the  point where the current  fiber was resumed.
 * The passed  objects would  be the return  value of  rb_fiber_resume().  This
 * fiber then suspends its execution until next time it is resumed.
 *
 * This function can  also raise arbitrary exceptions injected  from outside of
 * the fiber using rb_fiber_raise().
 *
 * ```ruby
 * exc = Class.new Exception
 *
 * f = Fiber.new do
 *   Fiber.yield
 * rescue exc => e
 *   puts e.message
 * end
 *
 * f.resume
 * f.raise exc, "Hi!"
 * ```
 *
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           Passed to rb_fiber_resume().
 * @exception  rb_eException  (See above)
 * @return     (See rb_fiber_resume() for details)
 */
VALUE rb_fiber_yield(int argc, const VALUE *argv);

/**
 * Identical to rb_fiber_yield(), except you can specify how to handle the last
 * element of the given array.
 *
 * @param[in]  argc            Number of objects of `argv`.
 * @param[in]  argv            Passed to rb_fiber_resume().
 * @param[in]  kw_splat        Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception  rb_eException   What was raised using `Fiber#raise`.
 * @return     (See rb_fiber_resume() for details)
 */
VALUE rb_fiber_yield_kw(int argc, const VALUE *argv, int kw_splat);

/**
 * Transfers control to  another fiber, resuming it from where  it last stopped
 * or starting  it if  it was not  resumed before.  The  calling fiber  will be
 * suspended much like in a call to rb_fiber_yield().
 *
 * The fiber  which receives  the transfer  call treats it  much like  a resume
 * call.  Arguments passed to transfer are treated like those passed to resume.
 *
 * The two style of control passing to and from fiber (one is rb_fiber_resume()
 * and  rb_fiber_yield(), another  is  rb_fiber_transfer() to  and from  fiber)
 * can't be freely mixed.
 *
 *   - If the  Fiber's lifecycle had  started with  transfer, it will  never be
 *     able to  yield or be  resumed control  passing, only finish  or transfer
 *     back.   (It  still can  resume  other  fibers  that  are allowed  to  be
 *     resumed.)
 *
 *   - If  the Fiber's  lifecycle  had started  with resume,  it  can yield  or
 *     transfer to  another Fiber, but  can receive  control back only  the way
 *     compatible with  the way it  was given away:  if it had  transferred, it
 *     only can  be transferred  back, and if  it had yielded,  it only  can be
 *     resumed back.  After that, it again can transfer or yield.
 *
 * If those rules are broken, rb_eFiberError is raised.
 *
 * For an  individual Fiber design,  yield/resume is  easier to use  (the Fiber
 * just gives away control,  it doesn't need to think about  who the control is
 * given to),  while transfer is more  flexible for complex cases,  allowing to
 * build arbitrary graphs of Fibers dependent on each other.
 *
 * @param[out]  fiber           Explicit control destination.
 * @param[in]   argc            Number of objects of `argv`.
 * @param[in]   argv            Passed to rb_fiber_resume().
 * @exception   rb_eFiberError  (See above)
 * @exception   rb_eException   What was raised using `Fiber#raise`.
 * @return      (See rb_fiber_resume() for details)
 */
VALUE rb_fiber_transfer(VALUE fiber, int argc, const VALUE *argv);

/**
 * Identical to rb_fiber_transfer(),  except you can specify how  to handle the
 * last element of the given array.
 *
 * @param[out]  fiber           Explicit control destination.
 * @param[in]   argc            Number of objects of `argv`.
 * @param[in]   argv            Passed to rb_fiber_resume().
 * @param[in]   kw_splat        Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception   rb_eFiberError  (See above)
 * @exception   rb_eException   What was raised using `Fiber#raise`.
 * @return      (See rb_fiber_resume() for details)
 */
VALUE rb_fiber_transfer_kw(VALUE fiber, int argc, const VALUE *argv, int kw_splat);

/**
 * Identical to rb_fiber_resume()  but instead of resuming  normal execution of
 * the passed fiber, it  raises the given exception in it.   From inside of the
 * fiber this would be seen as if rb_fiber_yield() raised.
 *
 * This function  does return in case  the passed fiber gracefully  handled the
 * passed exception.  But  if it does not, the raised  exception propagates out
 * of the passed fiber; this function then does not return.
 *
 * Parameters are passed to rb_make_exception()  to create an exception object.
 * See its document for what are allowed here.
 *
 * It is  a failure to  call this function against  a fiber which  is resuming,
 * have never run yet, or has already finished running.
 *
 * @param[out]  fiber           Where exception is raised.
 * @param[in]   argc            Passed as-is to rb_make_exception().
 * @param[in]   argv            Passed as-is to rb_make_exception().
 * @exception   rb_eFiberError  `fiber` is terminated etc.
 * @return      (See rb_fiber_resume() for details)
 */
VALUE rb_fiber_raise(VALUE fiber, int argc, const VALUE *argv);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_CONT_H */
