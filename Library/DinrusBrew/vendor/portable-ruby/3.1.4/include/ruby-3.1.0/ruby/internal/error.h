#ifndef RBIMPL_ERROR_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ERROR_H
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
 * @brief      Declares ::rb_raise().
 */
#include "ruby/internal/attr/cold.h"
#include "ruby/internal/attr/format.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

/**
 * @defgroup exception Exception handlings
 * @{
 */

/**
 * Warning  categories.  A  warning issued  using this  API can  be selectively
 * requested   /   suppressed   by   the  end-users.   For   instance   passing
 * `-W:no-deprecated`  to the  ruby process  would suppress  those warnings  in
 * deprecated category.
 *
 * @warning    There is no way to declare a new category (for now).
 */
typedef enum {
    /** Category unspecified. */
    RB_WARN_CATEGORY_NONE,

    /** Warning is for deprecated features. */
    RB_WARN_CATEGORY_DEPRECATED,

    /** Warning is for experimental features. */
    RB_WARN_CATEGORY_EXPERIMENTAL,

    RB_WARN_CATEGORY_ALL_BITS = 0x6 /* no RB_WARN_CATEGORY_NONE bit */
} rb_warning_category_t;

/** for rb_readwrite_sys_fail first argument */
enum rb_io_wait_readwrite {RB_IO_WAIT_READABLE, RB_IO_WAIT_WRITABLE};
/** @cond INTERNAL_MACRO */
#define RB_IO_WAIT_READABLE RB_IO_WAIT_READABLE
#define RB_IO_WAIT_WRITABLE RB_IO_WAIT_WRITABLE
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * This is the same as `$!` in Ruby.
 *
 * @retval   RUBY_Qnil  Not handling exceptions at the moment.
 * @retval   otherwise  The current exception in the current thread.
 * @ingroup  exception
 */
VALUE rb_errinfo(void);

/**
 * Sets the current exception (`$!`) to the given value.
 *
 * @param[in]  err            An instance of ::rb_eException, or ::RUBY_Qnil.
 * @exception  rb_eTypeError  What  is given  was  neither ::rb_eException  nor
 *                            ::RUBY_Qnil.
 * @note       Use  rb_raise()  instead to  raise  `err`.   This function  just
 *             assigns the given object to the global variable.
 * @ingroup    exception
 */
void rb_set_errinfo(VALUE err);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Exception  entry point.   By calling  this  function the  execution of  your
 * program gets interrupted to "raise" an  exception up to the callee entities.
 * Programs could "rescue" that exception, or could "ensure" some part of them.
 * If nobody cares  about such things, the raised exception  reaches at the top
 * of execution.  This yields abnormal end of the process.
 *
 * @param[in]  exc  A subclass of ::rb_eException.
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 * @exception  exc  The specified exception.
 * @note       It never returns.
 */
void rb_raise(VALUE exc, const char *fmt, ...);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 2)
/**
 * Raises the unsung "fatal" exception.  This is considered severe.  Nobody can
 * rescue  the  exception.  Once  raised,  process  termination is  inevitable.
 * However ensure clauses still run, so that resources are properly cleaned up.
 *
 * @param[in]  fmt        Format specifier string compatible with rb_sprintf().
 * @exception  rb_eFatal  An exception that you cannot rescue.
 * @note       It never returns.
 */
void rb_fatal(const char *fmt, ...);

RBIMPL_ATTR_COLD()
RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 2)
/**
 * Interpreter  panic  switch.   Immediate   process  termination  without  any
 * synchronisations shall  occur.  LOTS of  internal states, stack  traces, and
 * even  machine registers  are displayed  if possible  for debugging  purposes
 * then.
 *
 * @warning    Do not use this API.
 * @warning    You are not expected to use this API.
 * @warning    Why not just fix your code instead of calling this API?
 * @warning    It was a  bad idea to expose this API  to extension libraries at
 *             the first  place.  We just  cannot delete  it at this  point for
 *             backwards  compatibility.    That  doesn't  mean   everyone  are
 *             welcomed to call this function at will.
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 * @note       It never returns.
 */
void rb_bug(const char *fmt, ...);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL(())
/**
 * This is  a wrapper  of rb_bug()  which automatically  constructs appropriate
 * message from the passed errno.
 *
 * @param[in]  msg  Additional message to display.
 * @exception  err  C level errno.
 * @note       It never returns.
 */
void rb_bug_errno(const char *msg, int err);

RBIMPL_ATTR_NORETURN()
/**
 * Converts a C errno into a Ruby exception, then raises it.  For instance:
 *
 * ```CXX
 * static VALUE
 * foo(VALUE argv)
 * {
 *    const auto cmd = StringValueCStr(argv);
 *    const auto waitr = system(cmd);
 *    if (waitr == -1) {
 *        rb_sys_fail("system(3posix)"); // <-------------- this
 *    }
 *    else {
 *        return INT2FIX(fd);
 *    }
 * }
 * ```
 *
 * @param[in]  msg                  Additional message to raise.
 * @exception  rb_eSystemCallError  An exception representing errno.
 * @note       It never returns.
 */
void rb_sys_fail(const char *msg);

RBIMPL_ATTR_NORETURN()
/**
 * Identical to  rb_sys_fail(), except  it takes the  message in  Ruby's String
 * instead of C's.
 *
 * @param[in]  msg                  Additional message to raise.
 * @exception  rb_eSystemCallError  An exception representing errno.
 * @note       It never returns.
 */
void rb_sys_fail_str(VALUE msg);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((2))
/**
 * Identical to rb_sys_fail(), except it  takes additional module to extend the
 * exception object before raising.
 *
 * @param[in]  mod                  A ::rb_cModule instance.
 * @param[in]  msg                  Additional message to raise.
 * @exception  rb_eSystemCallError  An exception representing errno.
 * @note       It never returns.
 *
 * @internal
 *
 * Does anybody use it?
 */
void rb_mod_sys_fail(VALUE mod, const char *msg);

RBIMPL_ATTR_NORETURN()
/**
 * Identical to rb_mod_sys_fail(), except it takes the message in Ruby's String
 * instead of C's.
 *
 * @param[in]  mod                  A ::rb_cModule instance.
 * @param[in]  msg                  Additional message to raise.
 * @exception  rb_eSystemCallError  An exception representing errno.
 * @note       It never returns.
 */
void rb_mod_sys_fail_str(VALUE mod, VALUE msg);

RBIMPL_ATTR_NORETURN()
/**
 * Raises appropriate exception using the parameters.
 *
 * In Ruby level there are  rb_eEAGAINWaitReadable etc.  This function maps the
 * given parameter to an appropriate exception class, then raises it.
 *
 * @param[in]  waiting  Reason for the IO to wait.
 * @param[in]  msg      Additional message to raise.
 * @exception  rb_eEAGAINWaitWritable
 * @exception  rb_eEWOULDBLOCKWaitWritable
 * @exception  rb_eEINPROGRESSWaitWritable
 * @exception  rb_eEAGAINWaitReadable
 * @exception  rb_eEWOULDBLOCKWaitReadable
 * @exception  rb_eEINPROGRESSWaitReadable
 * @exception  rb_eSystemCallError
 * @note       It never returns.
 */
void rb_readwrite_sys_fail(enum rb_io_wait_readwrite waiting, const char *msg);

RBIMPL_ATTR_NORETURN()
/**
 * Breaks from a block.  Because you are  using a CAPI this is not as intuitive
 * as  it  sounds.   In order  for  this  function  to  properly work,  make  a
 * ::rb_block_call_func_t  function that  calls  it internally,  and pass  that
 * function to rb_block_call().
 *
 * @exception  rb_eLocalJumpError  Called from outside of a block.
 * @note       It never returns.
 */
void rb_iter_break(void);

RBIMPL_ATTR_NORETURN()
/**
 * Identical to  rb_iter_break(), except it  additionally takes the  "value" of
 * this breakage.  It  will be the evaluation result of  the iterator.  This is
 * kind  of  complicated; you  cannot  see  this as  a  "return  from a  block"
 * behaviour.  Take a look at this example:
 *
 * ```ruby
 * def foo(q)
 *   puts(w = yield(q))
 *   puts(e = yield(w))
 *   puts(r = yield(e))
 *   puts(t = yield(r))
 *   puts(y = yield(t))
 *   return "howdy!"
 * end
 *
 * x = foo(0) {|i|
 *   if i > 2
 *     break "hello!"
 *   else
 *     next i + 1
 *   end
 * }
 *
 * puts x
 * ```
 *
 * This script outputs 1, 2, 3, and hello.  Note that the value passed to break
 * becomes the  return value of  foo method, not the  value of yield.   This is
 * confusing, but  can be  handy on occasions  e.g.  when you  want to  bring a
 * local variable out of a block.
 *
 * @param[in]  val                 The value of the iterator.
 * @exception  rb_eLocalJumpError  Called from outside of a block.
 * @note       It never returns.
 */
void rb_iter_break_value(VALUE val);

RBIMPL_ATTR_NORETURN()
/**
 * Terminates the current execution context.  This  API is the entry point of a
 * "well-mannered"  termination  sequence.   When   called  from  an  extension
 * library, it  raises ::rb_eSystemExit exception.  Programs  could rescue that
 * exception.  Can cancel process exit then.  Otherwise, that exception results
 * in a process termination with the status passed to this function.
 *
 * @param[in]  status          Exit status, see also exit(3).
 * @exception  rb_eSystemExit  Exception representing the exit status.
 * @note       It never returns.
 *
 * @internal
 *
 * "When called from  an extension library"?  You might wonder.   In fact there
 * are chances for this function to be  called from outside of it, for instance
 * when dlopen(3)  failed.  In  case it  is not possible  for this  function to
 * raise an exception,  it does not (silently enters to  process cleanup).  But
 * that  is a  kind of  implementation detail  which extension  library authors
 * should not bother.
 */
void rb_exit(int status);

RBIMPL_ATTR_NORETURN()
/**
 * @exception  rb_eNotImpError
 * @note       It never returns.
 */
void rb_notimplement(void);

/**
 * Creates an exception object that represents the given C errno.
 *
 * @param[in]  err                  C level errno.
 * @param[in]  msg                  Additional message.
 * @retval     rb_eSystemCallError  An exception for the errno.
 */
VALUE rb_syserr_new(int err, const char * msg);

/**
 * Identical to rb_syserr_new(),  except it takes the message  in Ruby's String
 * instead of C's.
 *
 * @param[in]  n                    C level errno.
 * @param[in]  arg                  Additional message.
 * @retval     rb_eSystemCallError  An exception for the errno.
 */
VALUE rb_syserr_new_str(int n, VALUE arg);

RBIMPL_ATTR_NORETURN()
/**
 * Raises appropriate exception that represents a C errno.
 *
 * @param[in]  err                  C level errno.
 * @param[in]  msg                  Additional message to raise.
 * @exception  rb_eSystemCallError  An exception representing `err`.
 * @note       It never returns.
 */
void rb_syserr_fail(int err, const char *msg);

RBIMPL_ATTR_NORETURN()
/**
 * Identical to rb_syserr_fail(), except it  takes the message in Ruby's String
 * instead of C's.
 *
 * @param[in]  err                  C level errno.
 * @param[in]  msg                  Additional message to raise.
 * @exception  rb_eSystemCallError  An exception representing `err`.
 * @note       It never returns.
 */
void rb_syserr_fail_str(int err, VALUE msg);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL(())
/**
 * Identical  to rb_mod_sys_fail(),  except  it  does not  depend  on C  global
 * variable errno.  Pass it explicitly.
 *
 * @param[in]  mod                  A ::rb_cModule instance.
 * @param[in]  err                  C level errno.
 * @param[in]  msg                  Additional message to raise.
 * @exception  rb_eSystemCallError  An exception representing `err`.
 * @note       It never returns.
 */
void rb_mod_syserr_fail(VALUE mod, int err, const char *msg);

RBIMPL_ATTR_NORETURN()
/**
 * Identical to  rb_mod_syserr_fail(), except  it takes  the message  in Ruby's
 * String instead of C's.
 *
 * @param[in]  mod                  A ::rb_cModule instance.
 * @param[in]  err                  C level errno.
 * @param[in]  msg                  Additional message to raise.
 * @exception  rb_eSystemCallError  An exception representing `err`.
 * @note       It never returns.
 */
void rb_mod_syserr_fail_str(VALUE mod, int err, VALUE msg);

RBIMPL_ATTR_NORETURN()
/**
 * Identical to rb_readwrite_sys_fail(), except it  does not depend on C global
 * variable errno.  Pass it explicitly.
 *
 * @param[in]  waiting  Reason for the IO to wait.
 * @param[in]  err      C level errno.
 * @param[in]  msg      Additional message to raise.
 * @exception  rb_eEAGAINWaitWritable
 * @exception  rb_eEWOULDBLOCKWaitWritable
 * @exception  rb_eEINPROGRESSWaitWritable
 * @exception  rb_eEAGAINWaitReadable
 * @exception  rb_eEWOULDBLOCKWaitReadable
 * @exception  rb_eEINPROGRESSWaitReadable
 * @exception  rb_eSystemCallError
 * @note       It never returns.
 */
void rb_readwrite_syserr_fail(enum rb_io_wait_readwrite waiting, int err, const char *msg);

RBIMPL_ATTR_COLD()
RBIMPL_ATTR_NORETURN()
/**
 * Fails with the given object's type incompatibility to the type.
 *
 * It  seems this  function is  visible from  extension libraries  only because
 * RTYPEDDATA_TYPE() uses  it on RUBY_DEBUG.   So you can basically  ignore it;
 * use some other fine-grained method instead.
 *
 * @param[in]  self           The object in question.
 * @param[in]  t              Expected type of the object.
 * @exception  rb_eTypeError  `self` not in type `t`.
 * @note       It never returns.
 * @note       The second  argument must  have been an  enum ::ruby_value_type,
 *             but for  historical reasons it  remains to  be an int  (in other
 *             words we see no benefits fixing this bug).
 */
void rb_unexpected_type(VALUE self, int t);

/**
 * @private
 *
 * This  is an  implementation detail  of #ruby_verbose.   Please don't  use it
 * directly.
 *
 * @retval  Qnil       Interpreter is quiet.
 * @retval  Qfalse     Interpreter is kind of chatty.
 * @retval  otherwise  Interpreter is very verbose.
 */
VALUE *rb_ruby_verbose_ptr(void);

/**
 * @private
 *
 * This  is an  implementation  detail  of #ruby_debug.   Please  don't use  it
 * directly.
 *
 * @retval  Qnil       Interpreter not in debug mode.
 * @retval  Qfalse     Interpreter not in debug mode.
 * @retval  otherwise  Interpreter is in debug mode.
 */
VALUE *rb_ruby_debug_ptr(void);

/**
 * This variable  controls whether the  interpreter is in debug  mode.  Setting
 * this  to  some truthy  value  is  equivalent to  passing  `-W`  flag to  the
 * interpreter.  Setting this  to ::Qfalse is equivalent to  passing `-W1` flag
 * to the interpreter.   Setting this to ::Qnil is equivalent  to passing `-W0`
 * flag to the interpreter.
 *
 * @retval  Qnil       Interpreter is quiet.
 * @retval  Qfalse     Interpreter is kind of chatty.
 * @retval  otherwise  Interpreter is very verbose.
 */
#define ruby_verbose (*rb_ruby_verbose_ptr())

/**
 * This variable  controls whether the  interpreter is in debug  mode.  Setting
 * this  to  some truthy  value  is  equivalent to  passing  `-d`  flag to  the
 * interpreter.
 *
 * @retval  Qnil       Interpreter not in debug mode.
 * @retval  Qfalse     Interpreter not in debug mode.
 * @retval  otherwise  Interpreter is in debug mode.
 */
#define ruby_debug   (*rb_ruby_debug_ptr())

/* reports if `-W' specified */
RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 2)
/**
 * Issues a warning.
 *
 * In  ruby, warnings  these  days  are tightly  coupled  with the  rb_mWarning
 * constant and its `warn` singleton method.   This CAPI is just a thin wrapper
 * of it;  everything passed  are formatted like  what rb_sprintf()  does, then
 * passed  through   to  the  method.    Programs  can  have  their   own  `def
 * Warning.warn` at will  to do whatever they want, from  ignoring the warnings
 * at all to sinking them to some  BigQuery data set via a Fluentd cluster.  By
 * default,  the method  just emits  its passed  contents to  ::rb_stderr using
 * rb_io_write().
 *
 * @note       This function is affected by the `-W` flag.
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
void rb_warning(const char *fmt, ...);

RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Identical to rb_warning(), except it takes additional "category" parameter.
 *
 * @param[in]  cat  Name of a known category.
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 */
void rb_category_warning(rb_warning_category_t cat, const char *fmt, ...);

RBIMPL_ATTR_NONNULL((1, 3))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 3, 4)
/**
 * Issues a compile-time warning  that happens at `__file__:__line__`.  Purpose
 * of this function being exposed to CAPI is unclear.
 *
 * @note       This function is affected by the `-W` flag.
 * @param[in]  file  The path corresponding to Ruby level `__FILE__`.
 * @param[in]  line  The number corresponding to Ruby level `__LINE__`.
 * @param[in]  fmt   Format specifier string compatible with rb_sprintf().
 */
void rb_compile_warning(const char *file, int line, const char *fmt, ...);

RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 2)
/**
 * Identical to rb_sys_fail(), except it does  not raise an exception to render
 * a warning instead.
 *
 * @note       This function is affected by the `-W` flag.
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 */
void rb_sys_warning(const char *fmt, ...);

/* reports always */
RBIMPL_ATTR_COLD()
RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 2)
/**
 * Identical to  rb_warning(), except it  reports always regardless  of runtime
 * `-W` flag.
 *
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 */
void rb_warn(const char *fmt, ...);

RBIMPL_ATTR_COLD()
RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Identical to  rb_category_warning(), except it reports  always regardless of
 * runtime `-W` flag.
 *
 * @param[in]  cat  Category e.g. deprecated.
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 */
void rb_category_warn(rb_warning_category_t cat, const char *fmt, ...);

RBIMPL_ATTR_NONNULL((1, 3))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 3, 4)
/**
 * Identical to  rb_compile_warning(), except  it reports always  regardless of
 * runtime `-W` flag.
 *
 * @param[in]  file  The path corresponding to Ruby level `__FILE__`.
 * @param[in]  line  The number corresponding to Ruby level `__LINE__`.
 * @param[in]  fmt   Format specifier string compatible with rb_sprintf().
 */
void rb_compile_warn(const char *file, int line, const char *fmt, ...);

RBIMPL_ATTR_NONNULL((2, 4))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 4, 5)
/**
 * Identical to  rb_compile_warn(), except  it also accepts category.
 *
 * @param[in]  cat   Category e.g. deprecated.
 * @param[in]  file  The path corresponding to Ruby level `__FILE__`.
 * @param[in]  line  The number corresponding to Ruby level `__LINE__`.
 * @param[in]  fmt   Format specifier string compatible with rb_sprintf().
 */
void rb_category_compile_warn(rb_warning_category_t cat, const char *file, int line, const char *fmt, ...);

/** @} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_ERROR_H */
