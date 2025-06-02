#ifndef RUBY_THREAD_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_THREAD_H 1
/**
 * @file
 * @author     $Author: matz $
 * @date       Tue Jul 10 17:35:43 JST 2012
 * @copyright  Copyright (C) 2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/intern/thread.h" /* rb_unblock_function_t */
#include "ruby/internal/dllexport.h"

/**
 * @name Flags for rb_nogvl()
 *
 * @{
 */

/**
 * Passing  this  flag to  rb_nogvl()  prevents  it from  checking  interrupts.
 * Interrupts  can  impact  your  program negatively.   For  instance  consider
 * following callback function:
 *
 * ```CXX
 * static inline int fd; // set elsewhere.
 * static inline auto callback(auto buf) {
 *   auto tmp = ruby_xmalloc(BUFSIZ);
 *   auto ret = ruby_xmalloc(sizeof(ssize_t));  // (a)
 *   auto n = read(fd, tmp, BUFSIZ);            // (b)
 *   memcpy(buf, tmp, n);                       // (c)
 *   memcpy(ret, n, sizeof(n));
 *   ruby_xfree(tmp);
 *   return ret;
 * }
 * ```
 *
 * Here, if it gets interrupted at (a)  or (b), `read(2)` is cancelled and this
 * function leaks memory (which is not a good thing of course, but...).  But if
 * it gets interrupted at (c), where `read(2)` is already done, interruption is
 * way more catastrophic because what was read gets lost.  To reroute this kind
 * of problem you should set this flag.  And check interrupts elsewhere at your
 * own risk.
 */
#define RB_NOGVL_INTR_FAIL       (0x1)

/**
 * Passing  this  flag   to  rb_nogvl()  indicates  that  the   passed  UBF  is
 * async-signal-safe.   An UBF  could  be  async safe,  and  that makes  things
 * simpler.   However async  unsafe UBFs  are just  okay.  If  unsure, you  can
 * safely leave it unspecified.
 *
 * @internal
 *
 * This makes sense only in case of POSIX threads.
 */
#define RB_NOGVL_UBF_ASYNC_SAFE  (0x2)

/** @} */

RBIMPL_SYMBOL_EXPORT_BEGIN()

RBIMPL_ATTR_NONNULL((1))
/**
 * (Re-)acquires the GVL.   This manoeuvre makes it possible  for an out-of-GVL
 * routine to one-shot call a ruby method.
 *
 * What this function does:
 *
 *  1. Blocks until it acquires the GVL.
 *  2. Calls the passed function.
 *  3. Releases the GVL.
 *  4. Returns what was returned form the passed function.
 *
 * @param[in]      func   What to call with GVL.
 * @param[in,out]  data1  Passed as-is to `func`.
 * @return         What was returned from `func`.
 * @warning        `func` must not return a Ruby object.  If it did such return
 *                 value would escape from GC's scope; would not be marked.
 * @warning        Global escapes from this  function just yield whatever fatal
 *                 undefined behaviours.   You must make sure  that `func` does
 *                 not   raise,   by   properly   rescuing   everything   using
 *                 e.g. rb_protect().
 * @warning        You  cannot convert  a non-Ruby  thread into  a Ruby  thread
 *                 using this API.  This function  makes sense only from inside
 *                 of a rb_thread_call_without_gvl()'s callback.
 */
void *rb_thread_call_with_gvl(void *(*func)(void *), void *data1);

RBIMPL_ATTR_NONNULL((1))
/**
 * Allows the passed function to run in parallel with other Ruby threads.
 *
 * What this function does:
 *
 *  1. Checks (and handles) pending interrupts.
 *  2. Releases the GVL. (Others can run here in parallel...)
 *  3. Calls the passed function.
 *  4. Blocks until it re-acquires the GVL.
 *  5. Checks interrupts that happened between 2 to 4.
 *
 * In case  other threads  interfaced with  this thread  using rb_thread_kill()
 * etc., the  passed UBF  is additionally called.   See ::rb_unblock_function_t
 * for details.
 *
 * Unlike rb_thread_call_without_gvl2()  this function  also reacts  to signals
 * etc.
 *
 * @param[in]      func   A function to call without GVL.
 * @param[in,out]  data1  Passed as-is to `func`.
 * @param[in]      ubf    An UBF to cancel `func`.
 * @param[in,out]  data2  Passed as-is to `ubf`.
 * @return         What `func` returned, or 0 in case `ubf` cancelled `func`.
 * @warning        You cannot use  most of Ruby C APIs like  calling methods or
 *                 raising exceptions from  any of the functions  passed to it.
 *                 If that  is dead necessary use  rb_thread_call_with_gvl() to
 *                 re-acquire the GVL.
 * @warning        In short, this API is difficult.  @ko1 recommends you to use
 *                 other ways if any.  We lack experiences to use this API.  If
 *                 you  find any  corner cases  etc., please  report it  to the
 *                 devs.
 * @warning        Releasing and re-acquiring the GVL are expensive operations.
 *                 For a short-running `func`, it  might be faster to just call
 *                 `func` with blocking everything  else.  Be sure to benchmark
 *                 your code to see if it is actually worth releasing the GVL.
 */
void *rb_thread_call_without_gvl(void *(*func)(void *), void *data1,
                                 rb_unblock_function_t *ubf, void *data2);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to rb_thread_call_without_gvl(), except it does not interface with
 * signals etc.  As described in  #RB_NOGVL_INTR_FAIL, interrupts can hurt you.
 * In case this function detects an interrupt, it returns immediately.  You can
 * record progress  of your  callback and  check it  after returning  from this
 * function.
 *
 * What this function does:
 *
 *  1. Checks for pending interrupts and if any, just returns.
 *  2. Releases the GVL. (Others can run here in parallel...)
 *  3. Calls the passed function.
 *  4. Blocks until it re-acquires the GVL.
 *
 * @param[in]      func   A function to call without GVL.
 * @param[in,out]  data1  Passed as-is to `func`.
 * @param[in]      ubf    An UBF to cancel `func`.
 * @param[in,out]  data2  Passed as-is to `ubf`.
 * @return         What `func` returned, or 0 in case `func` did not return.
 */
void *rb_thread_call_without_gvl2(void *(*func)(void *), void *data1,
                                  rb_unblock_function_t *ubf, void *data2);

/*
 * XXX: unstable/unapproved - out-of-tree code should NOT not depend
 * on this until it hits Ruby 2.6.1
 */

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical  to  rb_thread_call_without_gvl(),  except it  additionally  takes
 * "flags" that change the behaviour.
 *
 * @param[in]      func   A function to call without GVL.
 * @param[in,out]  data1  Passed as-is to `func`.
 * @param[in]      ubf    An UBF to cancel `func`.
 * @param[in,out]  data2  Passed as-is to `ubf`.
 * @param[in]      flags  Flags.
 * @return         What `func` returned, or 0 in case `func` did not return.
 */
void *rb_nogvl(void *(*func)(void *), void *data1,
               rb_unblock_function_t *ubf, void *data2,
               int flags);

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define RUBY_CALL_WO_GVL_FLAG_SKIP_CHECK_INTS_AFTER 0x01

/**
 * @private
 * @deprecated  It seems even in the old days it made no sense...?
 */
#define RUBY_CALL_WO_GVL_FLAG_SKIP_CHECK_INTS_

/**
 * Triggered when a new thread is started.
 *
 * @note       The callback will be called *without* the GVL held.
 */
#define RUBY_INTERNAL_THREAD_EVENT_STARTED    1 << 0

/**
* Triggered when a thread attempt to acquire the GVL.
*
* @note       The callback will be called *without* the GVL held.
*/
#define RUBY_INTERNAL_THREAD_EVENT_READY      1 << 1 /** acquiring GVL */

/**
 * Triggered when a thread successfully acquired the GVL.
 *
 * @note       The callback will be called *with* the GVL held.
 */
#define RUBY_INTERNAL_THREAD_EVENT_RESUMED    1 << 2 /** acquired GVL */

/**
 * Triggered when a thread released the GVL.
 *
 * @note       The callback will be called *without* the GVL held.
 */
#define RUBY_INTERNAL_THREAD_EVENT_SUSPENDED  1 << 3 /** released GVL */

/**
 * Triggered when a thread exits.
 *
 * @note       The callback will be called *without* the GVL held.
 */
#define RUBY_INTERNAL_THREAD_EVENT_EXITED     1 << 4 /** thread terminated */

#define RUBY_INTERNAL_THREAD_EVENT_MASK       0xff /** All Thread events */

typedef struct rb_internal_thread_event_data {
   VALUE thread;
} rb_internal_thread_event_data_t;

typedef void (*rb_internal_thread_event_callback)(rb_event_flag_t event,
              const rb_internal_thread_event_data_t *event_data,
              void *user_data);
typedef struct rb_internal_thread_event_hook rb_internal_thread_event_hook_t;

/**
 * Registers a thread event hook function.
 *
 * @param[in]  func    A callback.
 * @param[in]  events  A set of events that `func` should run.
 * @param[in]  data    Passed as-is to `func`.
 * @return     An opaque pointer to the hook, to unregister it later.
 * @note       This functionality is a noop on Windows and WebAssembly.
 * @note       The callback will be called without the GVL held, except for the
 *             RESUMED event.
 * @note       Callbacks are not guaranteed to be executed on the native threads
 *             that corresponds to the Ruby thread. To identify which Ruby thread
 *             the event refers to, you must use `event_data->thread`.
 * @warning    This function MUST not be called from a thread event callback.
 */
rb_internal_thread_event_hook_t *rb_internal_thread_add_event_hook(
        rb_internal_thread_event_callback func, rb_event_flag_t events,
        void *data);


/**
 * Unregister the passed hook.
 *
 * @param[in]  hook.  The hook to unregister.
 * @return     Whether the hook was found and unregistered.
 * @note       This functionality is a noop on Windows and WebAssembly.
 * @warning    This function MUST not be called from a thread event callback.
*/
bool rb_internal_thread_remove_event_hook(
        rb_internal_thread_event_hook_t * hook);


typedef int rb_internal_thread_specific_key_t;
#define RB_INTERNAL_THREAD_SPECIFIC_KEY_MAX 8
/**
 * Create a key to store thread specific data.
 *
 * These APIs are designed for tools using
 * rb_internal_thread_event_hook APIs.
 *
 * Note that only `RB_INTERNAL_THREAD_SPECIFIC_KEY_MAX` keys
 * can be created. raises `ThreadError` if exceeded.
 *
 * Usage:
 *   // at initialize time:
 *   int tool_key; // gvar
 *   Init_tool() {
 *     tool_key = rb_internal_thread_specific_key_create();
 *   }
 *
 *   // at any timing:
 *   rb_internal_thread_specific_set(thread, tool_key, per_thread_data);
 *   ...
 *   per_thread_data = rb_internal_thread_specific_get(thread, tool_key);
 */
rb_internal_thread_specific_key_t rb_internal_thread_specific_key_create(void);

/**
 * Get thread and tool specific data.
 *
 * This function is async signal safe and thread safe.
 */
void *rb_internal_thread_specific_get(VALUE thread_val, rb_internal_thread_specific_key_t key);

/**
 * Set thread and tool specific data.
 *
 * This function is async signal safe and thread safe.
 */
void rb_internal_thread_specific_set(VALUE thread_val, rb_internal_thread_specific_key_t key, void *data);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_THREAD_H */
