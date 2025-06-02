#ifndef RBIMPL_INTERN_PROCESS_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_PROCESS_H
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
 * @brief      Public APIs related to ::rb_mProcess.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/config.h"      /* rb_pid_t is defined here. */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* process.c */

/**
 * Wait for the specified process to terminate, reap it, and return its status.
 *
 * @param[in] pid The process ID to wait for.
 * @param[in] flags The flags to pass to waitpid(2).
 * @return VALUE An instance of Process::Status.
 */
VALUE rb_process_status_wait(rb_pid_t pid, int flags);

/**
 * Sets the "last status", or the `$?`.
 *
 * @param[in]  status  The termination status, as defined in `waitpid(3posix)`.
 * @param[in]  pid     The last child of the current process.
 * @post       `$?` is updated.
 */
void rb_last_status_set(int status, rb_pid_t pid);

/**
 * Queries the "last status", or the `$?`.
 *
 * @retval  RUBY_Qnil  The current thread has no dead children.
 * @retval  otherwise  An instance of Process::Status  describing the status of
 *                     the child that was most recently `wait`-ed.
 */
VALUE rb_last_status_get(void);

RBIMPL_ATTR_NONNULL(())
/**
 * Executes a shell command.
 *
 * @warning    THIS FUNCTION RETURNS on error!
 * @param[in]  cmd  Passed to the shell.
 * @retval     -1   Something prevented the command execution.
 * @post       Upon successful execution this function doesn't return.
 * @post       In case it returns the `errno` is set properly.
 */
int rb_proc_exec(const char *cmd);

RBIMPL_ATTR_NORETURN()
/**
 * Replaces the current process by running the given external command.  This is
 * the implementation of `Kernel#exec`.
 *
 * @param[in]  argc                 Number of objects in `argv`.
 * @param[in]  argv                 Command and its options to execute.
 * @exception  rb_eTypeError        Invalid options e.g. non-String argv.
 * @exception  rb_eArgError         Invalid options e.g. redirection cycle.
 * @exception  rb_eNotImpError      Not implemented e.g. no `setuid(2)`.
 * @exception  rb_eRuntimeError     `Process::UID.switch` in operation.
 * @exception  rb_eSystemCallError  `execve(2)` failed.
 * @warning    This function doesn't return.
 * @warning    On failure it raises.  On success the process is replaced.
 *
 * @internal
 *
 * @shyouhei have to say that the  rdoc for `Kernel#exec` is fairly incomplete.
 * AFAIK this function ultimately takes the following signature:
 *
 * ```rbs
 * type boolx  = bool | nil                # !=  `boolish`
 *
 * type rlim_t = Integer                   # rlim_cur
 *             | [ Integer, Integer ]      # rlim_cur, rlim_max
 *
 * type uid_t  = String                    # e.g. "root"
 *             | Integer                   # e.g. 0
 *
 * type gid_t  = String                    # e.g. "wheel"
 *             | Integer                   # e.g. 0
 *
 * type fmode  = String                    # e.g. "rb"
 *             | Integer                   # e.g. O_RDONLY | O_BINARY
 *
 * type mode_t = Integer                   # e.g. 0644
 *
 * type pgrp   = true                      # Creates a dedicated pgroup
 *             | 0                         # ditto
 *             | nil                       # Uses the current one
 *             | Integer                   # Uses this specific pgroup
 *
 * type fd     = :in                       # STDIN
 *             | :out                      # STDOUT
 *             | :err                      # STDERR
 *             | IO                        # This specific IO
 *             | Integer                   # A file descriptor of this #
 *
 * type src    = fd | [ fd ]
 * type dst    = :close                    # Intuitive
 *             | fd                        # Intuitive
 *             | String                    # Open a file at this path
 *             | [ String ]                # ... using O_RDONLY
 *             | [ String, fmode ]         # ... using this mode
 *             | [ String, fmode, mode_t ] # ... with a permission
 *             | [ :child, fd ]            # fd of child side
 *
 * type redir  = Hash[ src, dst ]
 *
 * # ----
 *
 * # Key-value pair of environment variables
 * type envp  = Hash[ String, String ]
 *
 * # Actual name (and the name passed to the subprocess if any)
 * type arg0  = String | [ String, String ]
 *
 * # Arbitrary string parameters
 * type argv  = String
 *
 * # Exec options:
 * type argh  = redir | {
 *   chdir:             String, # Working directory
 *   close_others:      boolx,  # O_CLOEXEC like behaviour
 *   gid:               gid_t,  # setegid(2)
 *   pgrooup:           pgrp,   # setpgrp(2)
 *   rlimit_as:         rlim_t, # setrlimit(2)
 *   rlimit_core:       rlim_t, # ditto
 *   rlimit_cpu:        rlim_t, # ditto
 *   rlimit_data:       rlim_t, # ditto
 *   rlimit_fsize:      rlim_t, # ditto
 *   rlimit_memlock:    rlim_t, # ditto
 *   rlimit_msgqueue:   rlim_t, # ditto
 *   rlimit_nice:       rlim_t, # ditto
 *   rlimit_nofile:     rlim_t, # ditto
 *   rlimit_nproc:      rlim_t, # ditto
 *   rlimit_rss:        rlim_t, # ditto
 *   rlimit_rtprio:     rlim_t, # ditto
 *   rlimit_rttime:     rlim_t, # ditto
 *   rlimit_sbsize:     rlim_t, # ditto
 *   rlimit_sigpending: rlim_t, # ditto
 *   rlimit_stack:      rlim_t, # ditto
 *   uid:               uid_t,  # seteuid(2)
 *   umask:             mode_t, # umask(2)
 *   unsetenv_others:   boolx   # Unset everything except the passed envp
 * }
 *
 * # ====
 *
 * class Kernel
 *   def self?.exec
 *     : (          arg0 cmd, *argv args           ) -> void
 *     | (          arg0 cmd, *argv args, argh opts) -> void
 *     | (envp env, arg0 cmd, *argv args           ) -> void
 *     | (envp env, arg0 cmd, *argv args, argh opts) -> void
 * end
 * ```
 */
VALUE rb_f_exec(int argc, const VALUE *argv);

/**
 * Waits for a process, with releasing GVL.
 *
 * @param[in]   pid        Process ID.
 * @param[out]  status     The wait status is filled back.
 * @param[in]   flags      Wait options.
 * @retval      -1         System call failed, errno set.
 * @retval      0          WNOHANG but no waitable children.
 * @retval      otherwise  A process ID that was `wait()`-ed.
 * @post        Upon successful return `status` is updated to have the process'
 *              status.
 * @note        `status` can be NULL.
 * @note        The arguments are passed  through to underlying system call(s).
 *              Can have special meanings.  For instance passing `(rb_pid_t)-1`
 *              to   `pid`   means   it   waits  for   any   processes,   under
 *              POSIX-compliant situations.
 */
rb_pid_t rb_waitpid(rb_pid_t pid, int *status, int flags);

/**
 * This is  a shorthand of  rb_waitpid without status  and flags.  It  has been
 * like this  since the very beginning.   The initial revision already  did the
 * same thing.  Not sure why, then, it has been named `syswait`.  AFAIK this is
 * different from how `wait(3posix)` works.
 *
 * @param[in]  pid  Passed to rb_waitpid().
 */
void rb_syswait(rb_pid_t pid);

/**
 * Identical  to rb_f_exec(),  except  it  spawns a  child  process instead  of
 * replacing the current one.
 *
 * @param[in]  argc              Number of objects in `argv`.
 * @param[in]  argv              Command and its options to execute.
 * @exception  rb_eTypeError     Invalid options e.g. non-String argv.
 * @exception  rb_eArgError      Invalid options e.g. redirection cycle.
 * @exception  rb_eNotImpError   Not implemented e.g. no `setuid(2)`.
 * @exception  rb_eRuntimeError  `Process::UID.switch` in operation.
 * @retval     -1                Child process died for some reason.
 * @retval     otherwise         The ID of the born child.
 *
 * @internal
 *
 * This  is _really_  identical  to rb_f_exec()  until  ultimately calling  the
 * system  call.    Almost  everything   are  shared   among  these   two  (and
 * rb_f_system()).
 */
rb_pid_t rb_spawn(int argc, const VALUE *argv);

/**
 * Identical  to rb_spawn(),  except  you can  additionally  know the  detailed
 * situation in case of abnormal parturitions.
 *
 * @param[in]   argc              Number of objects in `argv`.
 * @param[in]   argv              Command and its options to execute.
 * @param[out]  errbuf            Error description write-back buffer.
 * @param[in]   buflen            Number of bytes of `errbuf`, including NUL.
 * @exception   rb_eTypeError     Invalid options e.g. non-String argv.
 * @exception   rb_eArgError      Invalid options e.g. redirection cycle.
 * @exception   rb_eNotImpError   Not implemented e.g. no `setuid(2)`.
 * @exception   rb_eRuntimeError  `Process::UID.switch` in operation.
 * @retval      -1                Child process died for some reason.
 * @retval      otherwise         The ID of the born child.
 * @post        In case  of `-1`, at most  `buflen` bytes of the  reason why is
 *              written back to `errbuf`.
 */
rb_pid_t rb_spawn_err(int argc, const VALUE *argv, char *errbuf, size_t buflen);

/**
 * Gathers info about resources consumed by the current process.
 *
 * @param[in]  _  Not used.  Pass anything.
 * @return     An instance of `Process::Tms`.
 *
 * @internal
 *
 * This function  might or might  not exist depending on  `./configure` result.
 * It must be a portability hell.  Better not use.
 */
VALUE rb_proc_times(VALUE _);

/**
 * "Detaches"  a subprocess.   In POSIX  systems every  child processes  that a
 * process creates must be `wait(2)`-ed.  A child process that died yet has not
 * been  waited so  far  is called  a  "zombie", which  more  or less  consumes
 * resources.   This function  automates reclamation  of such  processes.  Once
 * after this function successfully returns  you can basically forget about the
 * child process.
 *
 * @param[in]  pid  Process to wait.
 * @return     An instance of ::rb_cThread which is `waitpid(2)`-ing `pid`.
 * @post       You can just forget about the return value.  GC reclaims it.
 * @post       You  can  know the  exit  status  by  querying `#value`  of  the
 *             return value (which is a blocking operation).
 */
VALUE rb_detach_process(rb_pid_t pid);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_PROCESS_H */
