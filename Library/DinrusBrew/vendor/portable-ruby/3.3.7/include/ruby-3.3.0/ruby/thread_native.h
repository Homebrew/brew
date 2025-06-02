#ifndef RUBY_THREAD_NATIVE_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_THREAD_NATIVE_H 1
/**
 * @file
 * @author     $Author: ko1 $
 * @date       Wed May 14 19:37:31 2014
 * @copyright  Copyright (C) 2014 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 *
 * This file contains wrapper APIs for native thread primitives
 * which Ruby interpreter uses.
 *
 * Now, we only support pthread and Windows threads.
 *
 * If you want to use Ruby's Mutex and so on to synchronize Ruby Threads,
 * please use Mutex directly.
 */

#if defined(_WIN32)
#include <windows.h>
typedef HANDLE rb_nativethread_id_t;

typedef union rb_thread_lock_union {
    HANDLE mutex;
    CRITICAL_SECTION crit;
} rb_nativethread_lock_t;

struct rb_thread_cond_struct {
    struct cond_event_entry *next;
    struct cond_event_entry *prev;
};

typedef struct rb_thread_cond_struct rb_nativethread_cond_t;

#elif defined(HAVE_PTHREAD_H)

#include <pthread.h>
typedef pthread_t rb_nativethread_id_t;
typedef pthread_mutex_t rb_nativethread_lock_t;
typedef pthread_cond_t rb_nativethread_cond_t;

#elif defined(__wasi__) // no-thread platforms

typedef struct rb_nativethread_id_t *rb_nativethread_id_t;
typedef struct rb_nativethread_lock_t *rb_nativethread_lock_t;
typedef struct rb_nativethread_cond_t *rb_nativethread_cond_t;

#elif defined(__DOXYGEN__)

/** Opaque type that holds an ID of a native thread. */
struct rb_nativethread_id_t;

/** Opaque type that holds a lock. */
struct rb_nativethread_lock_t;

/** Opaque type that holds a condition variable. */
struct rb_nativethread_cond_t;

#else
#error "unsupported thread type"

#endif

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Queries the ID of the native thread that is calling this function.
 *
 * @return The caller thread's native ID.
 */
rb_nativethread_id_t rb_nativethread_self(void);

/**
 * Fills the passed lock with an initial value.
 *
 * @param[out]  lock  A mutex to initialise.
 * @post        `lock` is updated to its initial state.
 *
 * @internal
 *
 * There is no data structure that  analogous to pthread_once_t in ruby.  It is
 * pretty  much tricky  (if  not  impossible) to  properly  initialise a  mutex
 * exactly once.
 */
void rb_nativethread_lock_initialize(rb_nativethread_lock_t *lock);

/**
 * Destroys the passed mutex.
 *
 * @param[out]  lock  A mutex to kill.
 * @post        `lock` is no longer eligible for other functions.
 *
 * @internal
 *
 * It  is  an  undefined  behaviour  (see  `pthread_mutex_destroy(3posix)`)  to
 * destroy a locked  mutex.  So it has  to be unlocked.  But  an unlocked mutex
 * can of course  be locked by another thread.  That's  the ultimate reason why
 * we do mutex.   There is an inevitable race condition  here.  2017 edition of
 * IEEE 1003.1 issue 7 says in its  rationale that "care must be taken".  Care?
 * How?
 *
 * @shyouhei thinks that POSIX is broken by design.
 */
void rb_nativethread_lock_destroy(rb_nativethread_lock_t *lock);

/**
 * Blocks until the current thread obtains a lock.
 *
 * @param[out]  lock  A mutex to lock.
 * @post        `lock` is owned by the current native thread.
 */
void rb_nativethread_lock_lock(rb_nativethread_lock_t *lock);

/**
 * Releases a lock.
 *
 * @param[out]  lock  A mutex to unlock.
 * @pre         `lock` is owned by the current native thread.
 * @post        `lock` is not owned by the current native thread.
 */
void rb_nativethread_lock_unlock(rb_nativethread_lock_t *lock);

/** @alias{rb_nativethread_lock_lock} */
void rb_native_mutex_lock(rb_nativethread_lock_t *lock);

/**
 * Identical  to  rb_native_mutex_lock(),  except  it  doesn't  block  in  case
 * rb_native_mutex_lock() would.
 *
 * @param[out]  lock   A mutex to lock.
 * @retval      0      `lock` is successfully owned by the current thread.
 * @retval      EBUSY  `lock` is owned by someone else.
 */
int  rb_native_mutex_trylock(rb_nativethread_lock_t *lock);

/** @alias{rb_nativethread_lock_unlock} */
void rb_native_mutex_unlock(rb_nativethread_lock_t *lock);

/** @alias{rb_nativethread_lock_initialize} */
void rb_native_mutex_initialize(rb_nativethread_lock_t *lock);

/** @alias{rb_nativethread_lock_destroy} */
void rb_native_mutex_destroy(rb_nativethread_lock_t *lock);

/**
 * Signals a condition variable.
 *
 * @param[out]  cond  A condition variable to ping.
 * @post        More than one threads waiting for `cond` gets signalled.
 * @note        This  function   can  spuriously  wake  multiple   threads  up.
 *              `pthread_cond_signal(3posix)` says  it can even  be "impossible
 *              to avoid  the unblocking of more  than one thread blocked  on a
 *              condition variable".  Just brace spurious wakeups.
 */
void rb_native_cond_signal(rb_nativethread_cond_t *cond);

/**
 * Signals a condition variable.
 *
 * @param[out]  cond  A condition variable to ping.
 * @post        All threads waiting for `cond` gets signalled.
 */
void rb_native_cond_broadcast(rb_nativethread_cond_t *cond);

/**
 * Waits for the passed condition variable to be signalled.
 *
 * @param[out]  cond   A condition variable to wait.
 * @param[out]  mutex  A mutex.
 * @pre         `mutex` is owned by the current thread.
 * @post        `mutex` is owned by the current thread.
 * @note        This can wake up spuriously.
 */
void rb_native_cond_wait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex);

/**
 * Identical to rb_native_cond_wait(), except  it additionally takes timeout in
 * msec resolution.  Timeouts can be detected by catching exceptions.
 *
 * @param[out]  cond                 A condition variable to wait.
 * @param[out]  mutex                A mutex.
 * @param[in]   msec                 Timeout.
 * @exception   rb_eSystemCallError  `Errno::ETIMEDOUT` for timeout.
 * @pre         `mutex` is owned by the current thread.
 * @post        `mutex` is owned by the current thread.
 * @note        This can wake up spuriously.
 */
void rb_native_cond_timedwait(rb_nativethread_cond_t *cond, rb_nativethread_lock_t *mutex, unsigned long msec);

/**
 * Fills the passed condition variable with an initial value.
 *
 * @param[out]  cond  A condition variable to initialise.
 * @post        `cond` is updated to its initial state.
 */
void rb_native_cond_initialize(rb_nativethread_cond_t *cond);

/**
 * Destroys the passed condition variable.
 *
 * @param[out]  cond  A condition variable to kill.
 * @post        `cond` is no longer eligible for other functions.
 */
void rb_native_cond_destroy(rb_nativethread_cond_t *cond);

RBIMPL_SYMBOL_EXPORT_END()
#endif
