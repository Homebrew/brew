#ifndef RBIMPL_INTERPRETER_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERPRETER_H
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
 * @brief      Interpreter embedding APIs.
 */
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * @defgroup embed CRuby Embedding APIs
 *
 * CRuby interpreter APIs. These are APIs to embed MRI interpreter into your
 * program.
 * These functions are not a part of Ruby extension library API.
 * Extension libraries of Ruby should not depend on these functions.
 *
 * @{
 */

/**
 * @defgroup ruby1 ruby(1) implementation
 *
 * A part of the implementation of ruby(1) command.
 * Other programs that embed Ruby interpreter do not always need to use these
 * functions.
 *
 * @{
 */

RBIMPL_ATTR_NONNULL(())
/**
 * Initializes the process for libruby.
 *
 * This function assumes this process is `ruby(1)` and it has just started.
 * Usually programs that embed CRuby interpreter may not call this function,
 * and may do their own initialization.
 *
 * @param[in]  argc  Pointer to process main's `argc`.
 * @param[in]  argv  Pointer to process main's `argv`.
 * @warning    `argc` and `argv` cannot be `NULL`.
 *
 * @internal
 *
 * AFAIK Ruby does write to argv, especially `argv[0][0]`, via setproctitle(3).
 * It is intentional that the argument is not const-qualified.
 */
void ruby_sysinit(int *argc, char ***argv);

/**
 * Calls ruby_setup() and check error.
 *
 * Prints errors and calls exit(3) if an error occurred.
 */
void ruby_init(void);

/**
 * Processes command line arguments and compiles the Ruby source to execute.
 *
 * This function does:
 *   - Processes the given command line flags and arguments for `ruby(1)`
 *   - Compiles the source code from the given argument, `-e` or `stdin`, and
 *   - Returns the compiled source as an opaque pointer to an internal data
 *     structure
 *
 * @param[in]  argc  Process main's `argc`.
 * @param[in]  argv  Process main's `argv`.
 * @return     An opaque pointer to the compiled source or an internal special
 *             value.  Pass it to ruby_executable_node() to detect which.
 * @see        ruby_executable_node
 */
void* ruby_options(int argc, char** argv);

/**
 * Checks the return value of ruby_options().
 *
 * ruby_options() sometimes returns a special value to indicate this process
 * should immediately exit. This function checks if the case. Also stores the
 * exit status that the caller have to pass to exit(3) into `*status`.
 *
 * @param[in]   n          A return value of ruby_options().
 * @param[out]  status     Pointer to the exit status of this process.
 * @retval      0          The given value is such a special value.
 * @retval      otherwise  The given opaque pointer is actually a compiled
 *                         source.
 */
int ruby_executable_node(void *n, int *status);

/**
 * Runs the given compiled source and exits this process.
 *
 * @param[in]  n             Opaque "node" pointer.
 * @retval     EXIT_SUCCESS  Successfully run the source.
 * @retval     EXIT_FAILURE  An error occurred.
 */
int ruby_run_node(void *n);

/* version.c */
/** Prints the version information of the CRuby interpreter to stdout. */
void ruby_show_version(void);

#ifndef ruby_show_copyright
/** Prints the copyright notice of the CRuby interpreter to stdout. */
void ruby_show_copyright(void);
#endif

/**
 * A convenience macro to call ruby_init_stack().
 * Must be placed just after variable declarations.
 */
#define RUBY_INIT_STACK \
    VALUE variable_in_this_stack_frame; \
    ruby_init_stack(&variable_in_this_stack_frame);
/** @} */

/**
 * Set stack bottom of Ruby implementation.
 *
 * You  must   call  this   function  before  any   heap  allocation   by  Ruby
 * implementation.  Or GC will break living objects.
 *
 * @param[in]  addr  A pointer somewhere on the stack, near its bottom.
 */
void ruby_init_stack(volatile VALUE *addr);

/**
 * Initializes the VM and builtin libraries.
 *
 * @retval  0          Initialization succeeded.
 * @retval  otherwise  An error occurred.
 *
 * @internal
 *
 * Though not  a part of our  public API, the return  value is in fact  an enum
 * ruby_tag_type.  You can  see the potential "otherwise" values  by looking at
 * vm_core.h.
 */
int ruby_setup(void);

/**
 * Destructs the VM.
 *
 * Runs the VM finalization processes as well as ruby_finalize(), and frees
 * resources used by the VM.
 *
 * @param[in]  ex  Default value to the return value.
 * @retval     EXIT_FAILURE  An error occurred.
 * @retval     ex            Successful cleanup.
 * @note       This function does not raise any exception.
 */
int ruby_cleanup(int ex);

/**
 * Runs the VM finalization processes.
 *
 * `END{}` and procs registered by `Kernel.#at_exit` are executed here. See the
 * Ruby language spec for more details.
 *
 * @note This function is allowed to raise an exception if an error occurred.
 */
void ruby_finalize(void);

RBIMPL_ATTR_NORETURN()
/** Calls ruby_cleanup() and exits the process. */
void ruby_stop(int);

/**
 * Checks for stack overflow.
 *
 * @retval  true   NG machine stack is about to overflow.
 * @retval  false  OK there still is a room in the stack.
 *
 * @internal
 *
 * Does anybody use it?  So far @shyouhei have never seen any actual use-case.
 */
int ruby_stack_check(void);

/**
 * Queries what Ruby thinks is the machine stack.  Ruby manages a region of
 * memory.  It calls that area the "machine stack".  By calling this function,
 * in spite of its name, you can obtain both one end of the stack and its
 * length at once.  Which means you can know the entire region.
 *
 * @param[out]  topnotch  On return the pointer points to the upmost address of
 *                        the macihne stack that Ruby knows.
 * @return      Length of the machine stack that Ruby knows.
 *
 * @internal
 *
 * Does anybody use it?  @shyouhei is quite skeptical if this is useful outside
 * of the VM.  Maybe it was a wrong idea to expose this API to 3rd parties.
 */
size_t ruby_stack_length(VALUE **topnotch);

/**
 * Identical to ruby_run_node(), except it returns an opaque execution status.
 * You can pass it to rb_cleanup().
 *
 * @param[in]  n          Opaque "node" pointer.
 * @retval     0          Successful end-of-execution.
 * @retval     otherwise  An error occurred.
 *
 * @internal
 *
 * Though not  a part of our  public API, the return  value is in fact  an enum
 * ruby_tag_type.  You can  see the potential "otherwise" values  by looking at
 * vm_core.h.
 */
int ruby_exec_node(void *n);

/**
 * Sets the current script name to this value.
 *
 * This is similar to `$0 = name` in Ruby level but also affects
 * `Method#location` and others.
 *
 * @param[in]  name  File name to set.
 */
void ruby_script(const char* name);

/**
 * Identical to ruby_script(), except it takes the name as a Ruby String
 * instance.
 *
 * @param[in]  name  File name to set.
 */
void ruby_set_script_name(VALUE name);

/** Defines built-in variables */
void ruby_prog_init(void);

/**
 * Sets argv that ruby understands.  Your program might have its own command
 * line parameters etc.  Handle them as you wish, and pass remaining parts of
 * argv here.
 *
 * @param[in]  argc  Number of elements of `argv`.
 * @param[in]  argv  Command line arguments.
 */
void ruby_set_argv(int argc, char **argv);

/**
 * Identical to ruby_options(), except it raises ruby-level exceptions on
 * failure.
 *
 * @param[in]  argc  Process main's `argc`.
 * @param[in]  argv  Process main's `argv`.
 * @return     An opaque "node" pointer.
 */
void *ruby_process_options(int argc, char **argv);

/**
 * Sets up `$LOAD_PATH`.
 *
 * @internal
 *
 * @shyouhei guesses this has to be called  at very later stage, at least after
 * the birth of object system.  But is not exactly sure when.
 */
void ruby_init_loadpath(void);

/**
 * Appends the given path to the end of the load path.
 *
 * @pre        ruby_init_loadpath() must be done beforehand.
 * @param[in]  path  The path you want to push to the load path.
 */
void ruby_incpush(const char *path);

/**
 * Clear signal handlers.
 *
 * Ruby installs its own signal handler (apart from those which user scripts
 * set).  This is to clear that.  Must be called when the ruby part terminates,
 * before switching to your program's own logic.
 */
void ruby_sig_finalize(void);

/** @} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERPRETER_H */
