#ifndef RBIMPL_INTERN_SIGNAL_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SIGNAL_H
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
 * @brief      Signal handling APIs.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* signal.c */

RBIMPL_ATTR_NONNULL(())
/**
 * Sends a signal ("kills") to processes.
 *
 * The first argument is the signal, either in:
 *
 *   - Numerical representation (e.g. `9`), or
 *   - Textual  representation   of  canonical   (e.g.   `:SIGKILL`)   name  or
 *     abbreviated (e.g. `:KILL`) name, either in ::rb_cSymbol or ::rb_cString.
 *
 * All the  remaining arguments are  numerical representations of  process IDs.
 * This function iterates over them to send the specified signal.
 *
 * You can specify both negative PIDs and negative signo to this function:
 *
 *   ```
 *    sig \ pid | >= 1 | == 0 | == -1 | <= -2
 *   ===========+======+======+=======+=======
 *        > 0   |  #1  |  #2  |  #3   |  #4
 *       == 0   |  #5  |  #6  |  #7   |  #8
 *        < 0   |  #9  |  #10 |      #11
 *   ```
 *
 *   - Case #1: When  signo and PID are both positive,  this function sends the
 *     specified signal to the specified process (intuitive).
 *
 *   - Case #2: When  signo is  positive and PID  is zero, this  function sends
 *     that signal to the current process group.
 *
 *   - Case #3: When signo is positive and  PID is -1, this function sends that
 *     signal to everything that the current process is allowed to kill.
 *
 *   - Case #4: When signo  is positive and PID is negative  (but not -1), this
 *     function sends that signal to every  processes in a process group, whose
 *     process group ID is the absolute value of the passed PID.
 *
 *   - Case #5: When  signo  is zero  and PID is  positive, this  function just
 *     checks  for the  existence of  the  specified process  and doesn't  send
 *     anything to  anyone.  In  case the process  is absent  `Errno::ESRCH` is
 *     raised.
 *
 *   - Case #6: When signo and PID are  both zero, this function checks for the
 *     existence of the current process group.   And it must do.  This function
 *     is effectively a no-op then.
 *
 *   - Case #7: When signo is zero and PID is -1, this function checks if there
 *     is any other  process that the current process can  kill.  At least init
 *     (PID 1) must exist, so this must not fail.
 *
 *   - Case #8: When  signo is  zero and  PID is  negative (but  not -1),  this
 *     function checks  if there is a  process group whose process  group ID is
 *     the absolute  value of  the passed  PID.  In case  the process  group is
 *     absent `Errno::ESRCH` is raised.
 *
 *   - Case #9: When signo is negative and PID is positive, this function sends
 *     the absolute value of the passed signo to the process group specified as
 *     the PID.
 *
 *   - Case #10: When signo is negative and  PID is zero, it is highly expected
 *     that this function  sends the absolute value of the  passed signo to the
 *     current  process   group.   Strictly  speaking,  IEEE   Std  1003.1-2017
 *     specifies that  this (`killpg(3posix)` with  an argument of zero)  is an
 *     undefined behaviour.  But no operating system  is known so far that does
 *     things differently.
 *
 *   - Case #11: When  signo and PID  are both negative, the  behaviour of this
 *     function  depends on  how `killpg(3)`  works.  On  Linux, it  seems such
 *     attempt is  strictly prohibited and  `Errno::EINVAL` is raised.   But on
 *     macOS, it seems it  tries to to send the signal  actually to the process
 *     group.
 *
 * @note       Above description is in fact different from how `kill(2)` works.
 *             We interpret the passed arguments before passing them through to
 *             system calls.
 * @param[in]  argc                 Number of objects in `argv`.
 * @param[in]  argv                 Signal, followed by target PIDs.
 * @exception  rb_eArgError         Unknown signal name.
 * @exception  rb_eSystemCallError  Various errors sending signal to processes.
 * @return     Something numeric.  The meaning of this return value is unclear.
 *             It seems in case of #1 above, this could be the body count.  But
 *             other cases remain mysterious.
 */
VALUE rb_f_kill(int argc, const VALUE *argv);

RBIMPL_ATTR_PURE()
/**
 * Queries  the name  of  the signal.   It returns  for  instance `"KILL"`  for
 * SIGKILL.
 *
 * @param[in]  signo      Signal number to query.
 * @retval     0          No such signal.
 * @retval     otherwise  A pointer  to a static C  string that is the  name of
 *                        the signal.
 * @warning    Don't free the return value.
 */
const char *ruby_signal_name(int signo);

/**
 * Pretends as if  there was no custom signal handler.   This function sets the
 * signal action to SIG_DFL, then kills itself.
 *
 * @param[in]  sig  The signal.
 * @post       Previous signal handler is lost.
 * @post       Passed signal is sent to the current process.
 *
 * @internal
 *
 * @shyouhei doesn't understand  the needs of this function  being visible from
 * extension libraries.
 */
void ruby_default_signal(int sig);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_SIGNAL_H */
