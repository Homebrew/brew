#ifndef RBIMPL_INTERN_THREAD_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_THREAD_H
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
 * @brief      Public APIs related to ::rb_cThread.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/config.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

struct timeval;

/* thread.c */

/**
 * Tries to switch  to another thread.  This function blocks  until the current
 * thread re-acquires the GVL.
 *
 * @exception  rb_eInterrupt  Operation interrupted.
 */
void rb_thread_schedule(void);

/**
 * Blocks the  current thread until  the given file  descriptor is ready  to be
 * read.
 *
 * @param[in]  fd                    A file descriptor.
 * @exception  rb_eIOError           Closed stream.
 * @exception  rb_eSystemCallError   Situations like EBADF.
 */
int rb_thread_wait_fd(int fd);

/**
 * Identical to rb_thread_wait_fd(), except it  blocks the current thread until
 * the given file descriptor is ready to be written.
 *
 * @param[in]  fd                    A file descriptor.
 * @exception  rb_eIOError           Closed stream.
 * @exception  rb_eSystemCallError   Situations like EBADF.
 */
int rb_thread_fd_writable(int fd);

/**
 * Notifies a closing of a file  descriptor to other threads.  Multiple threads
 * can wait for the given file descriptor  at once.  If such file descriptor is
 * closed, threads need to start propagating their exceptions.  This is the API
 * to kick that process.
 *
 * @param[in]  fd  A file descriptor.
 * @note       This function blocks  until all the threads waiting  for such fd
 *             have woken up.
 */
void rb_thread_fd_close(int fd);

/**
 * Checks if  the thread this  function is running is  the only thread  that is
 * currently alive.
 *
 * @retval  1  Yes it is.
 * @retval  0  No it isn't.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  There are Ractors these days.
 */
int rb_thread_alone(void);

/**
 * Blocks for the given period of time.
 *
 * @warning    This function can be interrupted by signals.
 * @param[in]  sec            Duration in seconds.
 * @exception  rb_eInterrupt  Interrupted.
 */
void rb_thread_sleep(int sec);

/**
 * Blocks indefinitely.
 *
 * @exception  rb_eInterrupt  Interrupted.
 */
void rb_thread_sleep_forever(void);

/**
 * Identical  to  rb_thread_sleep_forever(),  except the  thread  calling  this
 * function is considered "dead" when our deadlock checker is triggered.
 *
 * @exception  rb_eInterrupt  Interrupted.
 */
void rb_thread_sleep_deadly(void);

/**
 * Stops the current thread.  This is not the end of the thread's lifecycle.  A
 * stopped thread can later be woken up.
 *
 * @exception  rb_eThreadError  Stopping this thread would deadlock.
 * @retval     ::RUBY_Qnil      Always.
 *
 * @internal
 *
 * The return value makes no sense at all.
 */
VALUE rb_thread_stop(void);

/**
 * Marks a given thread as eligible for scheduling.
 *
 * @note  It may still remain blocked on I/O.
 * @note  This does not invoke the scheduler itself.
 *
 * @param[out]  thread           Thread in question to wake up.
 * @exception   rb_eThreadError  Stop flogging a dead horse.
 * @return      The passed thread.
 * @post        The passed thread is made runnable.
 */
VALUE rb_thread_wakeup(VALUE thread);

/**
 * Identical  to rb_thread_wakeup(),  except  it doesn't  raise  on an  already
 * killed thread.
 *
 * @param[out]  thread     A thread to wake up.
 * @retval      RUBY_Qnil  `thread` is already killed.
 * @retval      otherwise  `thread` is alive.
 * @post        The passed thread is made runnable, unless killed.
 */
VALUE rb_thread_wakeup_alive(VALUE thread);

/**
 * This is a rb_thread_wakeup() + rb_thread_schedule() combo.
 *
 * @note        There is no  guarantee that this function yields  to the passed
 *              thread.  It may still remain blocked on I/O.
 * @param[out]  thread           Thread in question to wake up.
 * @exception   rb_eThreadError  Stop flogging a dead horse.
 * @return      The passed thread.
 */
VALUE rb_thread_run(VALUE thread);

/**
 * Terminates the given thread.  Unlike a stopped thread, a killed thread could
 * never be revived.   This function does return, when passed  e.g.  an already
 * killed thread.   But if  the passed  thread is  the only  one, or  a special
 * thread called "main", then it also terminates the entire process.
 *
 * @param[out]  thread          The thread to terminate.
 * @exception   rb_eFatal       The passed thread is the running thread.
 * @exception   rb_eSystemExit  The passed thread is the last thread.
 * @return      The passed thread.
 * @post        Either the passed thread, or the process entirely, is killed.
 *
 * @internal
 *
 * It seems killing the main thread also kills the entire process even if there
 * are multiple running ractors.  No idea why.
 */
VALUE rb_thread_kill(VALUE thread);

RBIMPL_ATTR_NONNULL((1))
/**
 * Creates a Ruby thread that is backended by a C function.
 *
 * @param[in]      f                    The function to run on a thread.
 * @param[in,out]  g                    Passed through to `f`.
 * @exception      rb_eThreadError      Could not create a ruby thread.
 * @exception      rb_eSystemCallError  Situations like `EPERM`.
 * @return         Allocated instance of ::rb_cThread.
 * @note           This doesn't wait for anything.
 */
VALUE rb_thread_create(VALUE (*f)(void *g), void *g);

/**
 * Identical to rb_thread_sleep(), except it takes struct `timeval` instead.
 *
 * @warning    This function can be interrupted by signals.
 * @param[in]  time           Duration.
 * @exception  rb_eInterrupt  Interrupted.
 */
void rb_thread_wait_for(struct timeval time);

/**
 * Obtains the "current" thread.
 *
 * @return  The current thread  of the current ractor of  the current execution
 *          context.
 * @pre     This function must be called from a thread controlled by ruby.
 */
VALUE rb_thread_current(void);

/**
 * Obtains the "main" thread.  There are threads called main.  Historically the
 * (only) main thread was the one which  runs when the process boots.  Now that
 * we have Ractor, there are more than one main threads.
 *
 * @return  The  main thread  of the  current ractor  of the  current execution
 *          context.
 * @pre     This function must be called from a thread controlled by ruby.
 */
VALUE rb_thread_main(void);

/**
 * This  badly named  function reads  from a  Fiber local  storage.  When  this
 * function was  born there  was no  such thing  like a  Fiber.  The  world was
 * innocent.  But now...  This is a Fiber local storage.  Sorry.
 *
 * @param[in]  thread     Thread that the target Fiber is running.
 * @param[in]  key        The name of the Fiber local storage to read.
 * @retval     RUBY_Qnil  No such storage.
 * @retval     otherwise  The value stored at `key`.
 * @note       There in fact are "true"  thread local storage, but Ruby doesn't
 *             provide any interface of them to you, C programmers.
 */
VALUE rb_thread_local_aref(VALUE thread, ID key);

/**
 * This  badly named  function  writes to  a Fiber  local  storage.  When  this
 * function was  born there  was no  such thing  like a  Fiber.  The  world was
 * innocent.  But now...  This is a Fiber local storage.  Sorry.
 *
 * @param[in]  thread           Thread that the target Fiber is running.
 * @param[in]  key              The name of the Fiber local storage to write.
 * @param[in]  val              The new value of the storage.
 * @exception  rb_eFrozenError  `thread` is frozen.
 * @return     The passed `val` as-is.
 * @post       Fiber local storage `key` has value of `val`.
 * @note       There in fact are "true"  thread local storage, but Ruby doesn't
 *             provide any interface of them to you, C programmers.
 */
VALUE rb_thread_local_aset(VALUE thread, ID key, VALUE val);

/**
 * A `pthread_atfork(3posix)`-like  API.  Ruby  expects its child  processes to
 * call this function at the very beginning of their processes.  If you plan to
 * fork a process don't forget to call it.
 */
void rb_thread_atfork(void);

/**
 * :FIXME: situation  of this function  is unclear.   It seems nobody  uses it.
 * Maybe a good idea to KonMari.
 */
void rb_thread_atfork_before_exec(void);

/**
 * "Recursion" API entry  point.  This basically calls the  given function with
 * the given arguments, but additionally with  recursion flag.  The flag is set
 * to 1  if the  execution have  already experienced  the passed  `g` parameter
 * before.
 *
 * @param[in]      f  The function that possibly recurs.
 * @param[in,out]  g  Passed as-is to `f`.
 * @param[in,out]  h  Passed as-is to `f`.
 * @return         The return value of f.
 */
VALUE rb_exec_recursive(VALUE (*f)(VALUE g, VALUE h, int r), VALUE g, VALUE h);

/**
 * Identical to rb_exec_recursive(), except it  checks for the recursion on the
 * ordered pair of `{ g, p }` instead of just `g`.
 *
 * @param[in]      f  The function that possibly recurs.
 * @param[in,out]  g  Passed as-is to `f`.
 * @param[in]      p  Paired object for recursion detection.
 * @param[in,out]  h  Passed as-is to `f`.
 */
VALUE rb_exec_recursive_paired(VALUE (*f)(VALUE g, VALUE h, int r), VALUE g, VALUE p, VALUE h);

/**
 * Identical  to  rb_exec_recursive(),  except   it  calls  `f`  for  outermost
 * recursion only.  Inner recursions yield calls to rb_throw_obj().
 *
 * @param[in]      f  The function that possibly recurs.
 * @param[in,out]  g  Passed as-is to `f`.
 * @param[in,out]  h  Passed as-is to `f`.
 * @return         The return value of f.
 *
 * @internal
 *
 * It seems  nobody uses the "it  calls rb_throw_obj()" part of  this function.
 * @shyouhei doesn't understand the needs.
 */
VALUE rb_exec_recursive_outer(VALUE (*f)(VALUE g, VALUE h, int r), VALUE g, VALUE h);

/**
 * Identical to  rb_exec_recursive_outer(), except it checks  for the recursion
 * on the ordered pair of `{ g, p }`  instead of just `g`.  It can also be seen
 * as a  routine identical to  rb_exec_recursive_paired(), except it  calls `f`
 * for   outermost   recursion  only.    Inner   recursions   yield  calls   to
 * rb_throw_obj().
 *
 * @param[in]      f  The function that possibly recurs.
 * @param[in,out]  g  Passed as-is to `f`.
 * @param[in]      p  Paired object for recursion detection.
 * @param[in,out]  h  Passed as-is to `f`.
 *
 * @internal
 *
 * It seems  nobody uses the "it  calls rb_throw_obj()" part of  this function.
 * @shyouhei doesn't understand the needs.
 */
VALUE rb_exec_recursive_paired_outer(VALUE (*f)(VALUE g, VALUE h, int r), VALUE g, VALUE p, VALUE h);

/**
 * This is  the type of UBFs.   An UBF is  a function that unblocks  a blocking
 * region.  For instance when a thread is blocking due to `pselect(3posix)`, it
 * is highly expected that `pthread_kill(3posix)` can interrupt the system call
 * and  the  thread  could  revive.   Or  when a  thread  is  blocking  due  to
 * `waitpid(3posix)`, it  is highly  expected that  killing the  waited process
 * should suffice.  An UBF is a function that does such things.  Designing your
 * own UBF  needs deep understanding  of why  your blocking region  blocks, how
 * threads work in ruby, and a matter of luck.  It often is the case you simply
 * cannot cancel something that had already begun.
 *
 * @see rb_thread_call_without_gvl()
 */
typedef void rb_unblock_function_t(void *);

/**
 * @private
 *
 * This is an implementation detail.  Must be a mistake to be here.
 *
 * @internal
 *
 * Why is  this function type different  from what rb_thread_call_without_gvl()
 * takes?
 */
typedef VALUE rb_blocking_function_t(void *);

/**
 * Checks for  interrupts.  In ruby,  signals are  masked by default.   You can
 * call this function at  will to check if there are  pending signals.  In case
 * there are, they would be handled in this function.
 *
 * If your  extension library has a  function that takes a  long time, consider
 * calling it periodically.
 *
 * @note  It might switch to another thread.
 */
void rb_thread_check_ints(void);

/**
 * Checks if the  thread's execution was recently interrupted.   If called from
 * that thread, this function can be used to detect spurious wake-ups.
 *
 * @param[in]  thval      Thread in question.
 * @retval     0          The thread was not interrupted.
 * @retval     otherwise  The thread was interrupted recently.
 *
 * @internal
 *
 * Above description is not a lie.  But  actually the return value is an opaque
 * trap vector.  If you know which bit means which, you can know what happened.
 */
int rb_thread_interrupted(VALUE thval);

/**
 * A special  UBF for blocking IO  operations.  You need deep  understanding of
 * what this  actually do before using.   Basically you should not  use it from
 * extension libraries.  It is too easy to mess up.
 */
#define RUBY_UBF_IO RBIMPL_CAST((rb_unblock_function_t *)-1)

/**
 * A special UBF for blocking  process operations.  You need deep understanding
 * of what this actually do before using.  Basically you should not use it from
 * extension libraries.  It is too easy to mess up.
 */
#define RUBY_UBF_PROCESS RBIMPL_CAST((rb_unblock_function_t *)-1)

/* thread_sync.c */

/**
 * Creates a mutex.
 *
 * @return An allocated instance of rb_cMutex.
 */
VALUE rb_mutex_new(void);

/**
 * Queries if there are any threads that holds the lock.
 *
 * @param[in]  mutex  The mutex in question.
 * @retval     RUBY_Qtrue  The mutex is locked by someone.
 * @retval     RUBY_Qfalse The mutex is not locked by anyone.
 */
VALUE rb_mutex_locked_p(VALUE mutex);

/**
 * Attempts to lock the mutex, without  waiting for other threads to unlock it.
 * Failure in locking the mutex can be detected by the return value.
 *
 * @param[out]  mutex        The mutex to lock.
 * @retval      RUBY_Qtrue   Successfully locked by the current thread.
 * @retval      RUBY_Qfalse  Otherwise.
 * @note        This  function also  returns  ::RUBY_Qfalse when  the mutex  is
 *              already owned by the calling thread itself.
 */
VALUE rb_mutex_trylock(VALUE mutex);

/**
 * Attempts to lock the mutex.  It waits until the mutex gets available.
 *
 * @param[out]  mutex            The mutex to lock.
 * @exception   rb_eThreadError  Recursive deadlock situation.
 * @return      The passed mutex.
 * @post        The mutex is owned by the current thread.
 */
VALUE rb_mutex_lock(VALUE mutex);

/**
 * Releases the mutex.
 *
 * @param[out]  mutex            The mutex to unlock.
 * @exception   rb_eThreadError  The mutex is not owned by the current thread.
 * @return      The passed mutex.
 * @post        Upon successful return  the passed mutex is no  longer owned by
 *              the current thread.
 */
VALUE rb_mutex_unlock(VALUE mutex);

/**
 * Releases  the lock  held in  the mutex  and waits  for the  period of  time;
 * reacquires the lock on wakeup.
 *
 * @pre         The lock has to be owned by the current thread beforehand.
 * @param[out]  self             The target mutex.
 * @param[in]   timeout          Duration, in seconds, in ::rb_cNumeric.
 * @exception   rb_eArgError     `timeout` is negative.
 * @exception   rb_eRangeError   `timeout` is out of range of `time_t`.
 * @exception   rb_eThreadError  The mutex is not owned by the current thread.
 * @return      Number of seconds it actually slept.
 * @warning     It is a  failure not to check the return  value.  This function
 *              can return spuriously for various reasons.  Maybe other threads
 *              can  rb_thread_wakeup().   Maybe  an  end user  can  press  the
 *              Control and C  key from the interactive console.   On the other
 *              hand it  can also  take longer than  the specified.   The mutex
 *              could be locked by someone else.  It waits then.
 * @post        Upon successful return the passed mutex is owned by the current
 *              thread.
 *
 * @internal
 *
 * This  function is  called from  `ConditionVariable#wait`.   So it  is not  a
 * deprecated feature.   However @shyouhei  have never  seen any  similar mutex
 * primitive available in any other languages than Ruby.
 *
 * EDIT: In 2021,  @shyouhei asked @ko1 in person about  this API.  He answered
 * that it is his invention.  The  motivation behind its design is to eliminate
 * needs of condition variables as  primitives.  Unlike other languages, Ruby's
 * `ConditionVariable` class was written in pure-Ruby initially.  We don't have
 * to implement  machine-native condition  variables in  assembly each  time we
 * port Ruby to a new architecture.  This function made it possible.  "I felt I
 * was a genius when this idea came to me", said @ko1.
 *
 * `rb_cConditionVariable` is now written in C for speed, though.
 */
VALUE rb_mutex_sleep(VALUE self, VALUE timeout);

/**
 * Obtains the  lock, runs the passed  function, and releases the  lock when it
 * completes.
 *
 * @param[out]     mutex  The mutex to lock.
 * @param[in]      func   What to do during the mutex is locked.
 * @param[in,out]  arg    Passed as-is to `func`.
 */
VALUE rb_mutex_synchronize(VALUE mutex, VALUE (*func)(VALUE arg), VALUE arg);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_THREAD_H */
