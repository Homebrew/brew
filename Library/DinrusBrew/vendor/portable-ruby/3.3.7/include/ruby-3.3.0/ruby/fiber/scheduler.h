#ifndef RUBY_FIBER_SCHEDULER_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_FIBER_SCHEDULER_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Scheduler APIs.
 */
#include "ruby/internal/config.h"

#include <errno.h>

#ifdef STDC_HEADERS
#include <stddef.h> /* size_t */
#endif

#include "ruby/ruby.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/arithmetic.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

#define RUBY_FIBER_SCHEDULER_VERSION 2

struct timeval;

/**
 * Wrap a `ssize_t` and `int errno` into a single `VALUE`. This interface should
 * be used to safely capture results from system calls  like `read` and `write`.
 *
 * You should use `rb_fiber_scheduler_io_result_apply` to unpack the result of
 * this value and update `int errno`.
 *
 * You should not directly try to interpret the result value as it is considered
 * an opaque representation. However, the general representation is an integer
 * in the range of `[-int errno, size_t size]`. Linux generally restricts the
 * result of system calls like `read` and `write` to `<= 2^31` which means this
 * will typically fit within a single FIXNUM.
 *
 * @param[in]  result   The result of the system call.
 * @param[in]  error    The value of `errno`.
 * @return              A `VALUE` which contains the result and/or errno.
 */
static inline VALUE
rb_fiber_scheduler_io_result(ssize_t result, int error)
{
    if (result == -1) {
        return RB_INT2NUM(-error);
    }
    else {
        return RB_SIZE2NUM(result);
    }
}

/**
 * Apply an io result to the local thread, returning the value of the original
 * system call that created it and updating `int errno`.
 *
 * You should not directly try to interpret the result value as it is considered
 * an opaque representation.
 *
 * @param[in]  result   The `VALUE` which contains an errno and/or result size.
 * @post                Updates `int errno` with the value if negative.
 * @return              The original result of the system call.
 */
static inline ssize_t
rb_fiber_scheduler_io_result_apply(VALUE result)
{
    if (RB_FIXNUM_P(result) && RB_NUM2INT(result) < 0) {
        errno = -RB_NUM2INT(result);
        return -1;
    }
    else {
        return RB_NUM2SIZE(result);
    }
}

/**
 * Queries the  current scheduler of  the current  thread that is  calling this
 * function.
 *
 * @retval  RUBY_Qnil  No scheduler has  been set so far to  this thread (which
 *                     is the default).
 * @retval  otherwise  The scheduler that  was last set for  the current thread
 *                     with rb_fiber_scheduler_set().
 */
VALUE rb_fiber_scheduler_get(void);

/**
 * Destructively assigns  the passed  scheduler to that  of the  current thread
 * that is calling this function.  If the scheduler is set, non-blocking fibers
 * (created by `Fiber.new` with `blocking: false`, or by `Fiber.schedule`) call
 * that scheduler's  hook methods on  potentially blocking operations,  and the
 * current  thread  will  call  scheduler's  `#close`  method  on  finalisation
 * (allowing  the  scheduler  to  properly  manage  all  non-finished  fibers).
 * `scheduler`   can   be   an   object   of   any   class   corresponding   to
 * `Fiber::Scheduler` interface. Its implementation is up to the user.
 *
 * @param[in]  scheduler     The scheduler to set.
 * @exception  rb_eArgError  `scheduler` does not conform the interface.
 * @post       Current thread's scheduler is `scheduler`.
 */
VALUE rb_fiber_scheduler_set(VALUE scheduler);

/**
 * Identical to rb_fiber_scheduler_get(), except it also returns ::RUBY_Qnil in
 * case of a blocking fiber.  As blocking fibers do not participate schedulers'
 * scheduling this function can be handy.
 *
 * @retval  RUBY_Qnil  No scheduler is in effect.
 * @retval  otherwise  The scheduler that is in effect, if any.
 */
VALUE rb_fiber_scheduler_current(void);

/**
 * Identical to rb_fiber_scheduler_current(), except it queries for that of the
 * passed thread instead of the implicit current one.
 *
 * @param[in]  thread         Target thread.
 * @exception  rb_eTypeError  `thread` is not a thread.
 * @retval     RUBY_Qnil      No scheduler is in effect in `thread`.
 * @retval     otherwise      The scheduler that is in effect in `thread`.
 */
VALUE rb_fiber_scheduler_current_for_thread(VALUE thread);

/**
 * Converts the passed timeout to an expression that rb_fiber_scheduler_block()
 * etc. expects.
 *
 * @param[in]  timeout    A duration (can be `NULL`).
 * @retval     RUBY_Qnil  No timeout (blocks indefinitely).
 * @retval     otherwise  A timeout object.
 */
VALUE rb_fiber_scheduler_make_timeout(struct timeval *timeout);

/**
 * Closes the passed scheduler object.  This expects the scheduler to wait for
 * all fibers.  Thus the scheduler's main loop tends to start here.
 *
 * @param[in]  scheduler  Target scheduler.
 * @return     What `scheduler.close` returns.
 */
VALUE rb_fiber_scheduler_close(VALUE scheduler);

/**
 * Non-blocking  `sleep`.  Depending  on  scheduler  implementation,  this  for
 * instance switches to another fiber etc.
 *
 * @param[in]  scheduler  Target scheduler.
 * @param[in]  duration   Passed as-is to `scheduler.kernel_sleep`.
 * @return     What `scheduler.kernel_sleep` returns.
 */
VALUE rb_fiber_scheduler_kernel_sleep(VALUE scheduler, VALUE duration);

/**
 * Identical to rb_fiber_scheduler_kernel_sleep(), except  it can pass multiple
 * arguments.
 *
 * @param[in]  scheduler  Target scheduler.
 * @param[in]  argc       Number of objects of `argv`.
 * @param[in]  argv       Passed as-is to `scheduler.kernel_sleep`
 * @return     What `scheduler.kernel_sleep` returns.
 */
VALUE rb_fiber_scheduler_kernel_sleepv(VALUE scheduler, int argc, VALUE * argv);

/* Description TBW */
#if 0
VALUE rb_fiber_scheduler_timeout_after(VALUE scheduler, VALUE timeout, VALUE exception, VALUE message);
VALUE rb_fiber_scheduler_timeout_afterv(VALUE scheduler, int argc, VALUE * argv);
int rb_fiber_scheduler_supports_process_wait(VALUE scheduler);
#endif

/**
 * Non-blocking `waitpid`.  Depending  on  scheduler  implementation, this  for
 * instance switches to another fiber etc.
 *
 * @param[in]  scheduler  Target scheduler.
 * @param[in]  pid        Process ID to wait.
 * @param[in]  flags      Wait flags, e.g. `WUNTRACED`.
 * @return     What `scheduler.process_wait` returns.
 */
VALUE rb_fiber_scheduler_process_wait(VALUE scheduler, rb_pid_t pid, int flags);

/**
 * Non-blocking  wait  for  the  passed   "blocker",  which  is   for  instance
 * `Thread.join` or `Mutex.lock`.  Depending  on scheduler implementation, this
 * for instance switches to another fiber etc.
 *
 * @param[in]  scheduler  Target scheduler.
 * @param[in]  blocker    What blocks the current fiber.
 * @param[in]  timeout    Numeric timeout.
 * @return     What `scheduler.block` returns.
 */
VALUE rb_fiber_scheduler_block(VALUE scheduler, VALUE blocker, VALUE timeout);

/**
 * Wakes up a fiber previously blocked using rb_fiber_scheduler_block().
 *
 * @param[in]  scheduler  Target scheduler.
 * @param[in]  blocker    What was awaited for.
 * @param[in]  fiber      What to unblock.
 * @return     What `scheduler.unblock` returns.
 */
VALUE rb_fiber_scheduler_unblock(VALUE scheduler, VALUE blocker, VALUE fiber);

/**
 * Non-blocking version of rb_io_wait().  Depending on scheduler
 * implementation, this for instance switches to another fiber etc.
 *
 * The  "events" here  is a  Ruby level  integer, which  is an  OR-ed value  of
 * `IO::READABLE`, `IO::WRITABLE`, and `IO::PRIORITY`.
 *
 * @param[in]  scheduler  Target scheduler.
 * @param[in]  io         An io object to wait.
 * @param[in]  events     An integer set of interests.
 * @param[in]  timeout    Numeric timeout.
 * @return     What `scheduler.io_wait` returns.
 */
VALUE rb_fiber_scheduler_io_wait(VALUE scheduler, VALUE io, VALUE events, VALUE timeout);

/**
 * Non-blocking  wait until the passed  IO  is ready  for reading.   This is  a
 * special  case   of  rb_fiber_scheduler_io_wait(),  where  the   interest  is
 * `IO::READABLE` and timeout is never.
 *
 * @param[in]  scheduler  Target scheduler.
 * @param[in]  io         An io object to wait.
 * @return     What `scheduler.io_wait` returns.
 */
VALUE rb_fiber_scheduler_io_wait_readable(VALUE scheduler, VALUE io);

/**
 * Non-blocking  wait until  the passed  IO  is ready  for writing.   This is a
 * special  case   of  rb_fiber_scheduler_io_wait(),  where  the   interest  is
 * `IO::WRITABLE` and timeout is never.
 *
 * @param[in]  scheduler  Target scheduler.
 * @param[in]  io         An io object to wait.
 * @return     What `scheduler.io_wait` returns.
 */
VALUE rb_fiber_scheduler_io_wait_writable(VALUE scheduler, VALUE io);

/**
 * Non-blocking version of `IO.select`.
 *
 * It's possible that this will be emulated using a thread, so you should not
 * rely on it for high performance.
 *
 * @param[in]  scheduler    Target scheduler.
 * @param[in]  readables    An array of readable objects.
 * @param[in]  writables    An array of writable objects.
 * @param[in]  exceptables  An array of objects that might encounter exceptional conditions.
 * @param[in]  timeout      Numeric timeout or nil.
 * @return     What `scheduler.io_select` returns, normally a 3-tuple of arrays of ready objects.
 */
VALUE rb_fiber_scheduler_io_select(VALUE scheduler, VALUE readables, VALUE writables, VALUE exceptables, VALUE timeout);

/**
 * Non-blocking version of `IO.select`, `argv` variant.
 */
VALUE rb_fiber_scheduler_io_selectv(VALUE scheduler, int argc, VALUE *argv);

/**
 * Non-blocking read from the passed IO.
 *
 * @param[in]   scheduler    Target scheduler.
 * @param[in]   io           An io object to read from.
 * @param[in]   buffer       The buffer to read to.
 * @param[in]   length       The minimum number of bytes to read.
 * @param[in]   offset       The offset in the buffer to read from.
 * @retval      RUBY_Qundef  `scheduler` doesn't have `#io_read`.
 * @return      otherwise    What `scheduler.io_read` returns `[-errno, size]`.
 */
VALUE rb_fiber_scheduler_io_read(VALUE scheduler, VALUE io, VALUE buffer, size_t length, size_t offset);

/**
 * Non-blocking write to the passed IO.
 *
 * @param[in]   scheduler    Target scheduler.
 * @param[in]   io           An io object to write to.
 * @param[in]   buffer       The buffer to write from.
 * @param[in]   length       The minimum number of bytes to write.
 * @param[in]   offset       The offset in the buffer to write from.
 * @retval      RUBY_Qundef  `scheduler` doesn't have `#io_write`.
 * @return      otherwise    What `scheduler.io_write` returns `[-errno, size]`.
 */
VALUE rb_fiber_scheduler_io_write(VALUE scheduler, VALUE io, VALUE buffer, size_t length, size_t offset);

/**
 * Non-blocking read from the passed IO at the specified offset.
 *
 * @param[in]   scheduler    Target scheduler.
 * @param[in]   io           An io object to read from.
 * @param[in]   from         The offset to read from.
 * @param[in]   buffer       The buffer to read to.
 * @param[in]   length       The minimum number of bytes to read.
 * @param[in]   offset       The offset in the buffer to read to.
 * @retval      RUBY_Qundef  `scheduler` doesn't have `#io_read`.
 * @return      otherwise    What `scheduler.io_read` returns.
 */
VALUE rb_fiber_scheduler_io_pread(VALUE scheduler, VALUE io, rb_off_t from, VALUE buffer, size_t length, size_t offset);

/**
 * Non-blocking write to the passed IO at the specified offset.
 *
 * @param[in]   scheduler    Target scheduler.
 * @param[in]   io           An io object to write to.
 * @param[in]   from         The offset to write to.
 * @param[in]   buffer       The buffer to write from.
 * @param[in]   length       The minimum number of bytes to write.
 * @param[in]   offset       The offset in the buffer to write from.
 * @retval      RUBY_Qundef  `scheduler` doesn't have `#io_write`.
 * @return      otherwise    What `scheduler.io_write` returns.
 */
VALUE rb_fiber_scheduler_io_pwrite(VALUE scheduler, VALUE io, rb_off_t from, VALUE buffer, size_t length, size_t offset);

/**
 * Non-blocking read from the passed IO using a native buffer.
 *
 * @param[in]   scheduler    Target scheduler.
 * @param[in]   io           An io object to read from.
 * @param[in]   base         The memory to read to.
 * @param[in]   size         Size of the memory.
 * @param[in]   length       The minimum number of bytes to read.
 * @retval      RUBY_Qundef  `scheduler` doesn't have `#io_read`.
 * @return      otherwise    What `scheduler.io_read` returns.
 */
VALUE rb_fiber_scheduler_io_read_memory(VALUE scheduler, VALUE io, void *base, size_t size, size_t length);

/**
 * Non-blocking write to the passed IO using a native buffer.
 *
 * @param[in]   scheduler    Target scheduler.
 * @param[in]   io           An io object to write to.
 * @param[in]   base         The memory to write from.
 * @param[in]   size         Size of the memory.
 * @param[in]   length       The minimum number of bytes to write.
 * @retval      RUBY_Qundef  `scheduler` doesn't have `#io_write`.
 * @return      otherwise    What `scheduler.io_write` returns.
 */
VALUE rb_fiber_scheduler_io_write_memory(VALUE scheduler, VALUE io, const void *base, size_t size, size_t length);

/**
 * Non-blocking pread from the passed IO using a native buffer.
 *
 * @param[in]   scheduler    Target scheduler.
 * @param[in]   io           An io object to read from.
 * @param[in]   from         The offset to read from.
 * @param[in]   base         The memory to read to.
 * @param[in]   size         Size of the memory.
 * @param[in]   length       The minimum number of bytes to read.
 * @retval      RUBY_Qundef  `scheduler` doesn't have `#io_read`.
 * @return      otherwise    What `scheduler.io_read` returns.
 */
VALUE rb_fiber_scheduler_io_pread_memory(VALUE scheduler, VALUE io, rb_off_t from, void *base, size_t size, size_t length);

/**
 * Non-blocking pwrite to the passed IO using a native buffer.
 *
 * @param[in]   scheduler    Target scheduler.
 * @param[in]   io           An io object to write to.
 * @param[in]   from         The offset to write from.
 * @param[in]   base         The memory to write from.
 * @param[in]   size         Size of the memory.
 * @param[in]   length       The minimum number of bytes to write.
 * @retval      RUBY_Qundef  `scheduler` doesn't have `#io_write`.
 * @return      otherwise    What `scheduler.io_write` returns.
 */
VALUE rb_fiber_scheduler_io_pwrite_memory(VALUE scheduler, VALUE io, rb_off_t from, const void *base, size_t size, size_t length);

/**
 * Non-blocking close the given IO.
 *
 * @param[in]  scheduler    Target scheduler.
 * @param[in]  io           An io object to close.
 * @retval     RUBY_Qundef  `scheduler` doesn't have `#io_close`.
 * @return     otherwise    What `scheduler.io_close` returns.
 */
VALUE rb_fiber_scheduler_io_close(VALUE scheduler, VALUE io);

/**
 * Non-blocking DNS lookup.
 *
 * @param[in]  scheduler    Target scheduler.
 * @param[in]  hostname     A host name to query.
 * @retval     RUBY_Qundef  `scheduler` doesn't have `#address_resolve`.
 * @return     otherwise    What `scheduler.address_resolve` returns.
 */
VALUE rb_fiber_scheduler_address_resolve(VALUE scheduler, VALUE hostname);

/**
 * Create and schedule a non-blocking fiber.
 *
 */
VALUE rb_fiber_scheduler_fiber(VALUE scheduler, int argc, VALUE *argv, int kw_splat);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_FIBER_SCHEDULER_H */
