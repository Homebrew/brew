#ifndef RBIMPL_INTERN_SELECT_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SELECT_H
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
 * @brief      Public APIs to provide ::rb_fd_select().
 * @note       Functions  and  structs defined  in  this  header file  are  not
 *             necessarily ruby-specific.  They don't need ::VALUE etc.
 */
#include "ruby/internal/config.h"

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>         /* for NFDBITS (BSD Net/2) */
#endif

#include "ruby/internal/dllexport.h"

/* thread.c */
#if defined(NFDBITS) && defined(HAVE_RB_FD_INIT)
# include "ruby/internal/intern/select/largesize.h"
#elif defined(_WIN32)
# include "ruby/internal/intern/select/win32.h"
# /** Does nothing (defined for compatibility). */
# define rb_fd_resize(n, f) ((void)(f))
#else
# include "ruby/internal/intern/select/posix.h"
# /** Does nothing (defined for compatibility). */
# define rb_fd_resize(n, f) ((void)(f))
#endif

RBIMPL_SYMBOL_EXPORT_BEGIN()

struct timeval;

/**
 * Waits for multiple file descriptors at once.  This is basically a wrapper of
 * system-provided select() with releasing GVL, to allow other Ruby threads run
 * in parallel.
 *
 * @param[in]      nfds       Max FD in everything passed, plus one.
 * @param[in,out]  rfds       Set of FDs to wait for reads.
 * @param[in,out]  wfds       Set of FDs to wait for writes.
 * @param[in,out]  efds       Set of FDs to wait for OOBs.
 * @param[in,out]  timeout    Max blocking duration.
 * @retval         -1         Failed, errno set.
 * @retval          0         Timeout exceeded.
 * @retval         otherwise  Total number of file descriptors returned.
 * @post           `rfds` contains readable FDs.
 * @post           `wfds` contains writable FDs.
 * @post           `efds` contains exceptional FDs.
 * @post           `timeout` is the time left.
 * @note           All pointers are allowed to be null pointers.
 *
 * Although backend  threads can run in  parallel of this function,  touching a
 * file descriptor  from multiple threads  could be problematic.   For instance
 * what happens  when a  thread closes  a file descriptor  that is  selected by
 * someone else, vastly varies among operating systems.  You would better avoid
 * touching an fd from more than one threads.
 *
 * @internal
 *
 * Although  any file  descriptors are  possible here,  it makes  completely no
 * sense to pass  a descriptor that is  not `O_NONBLOCK`.  If you  want to know
 * the reason for  this limitatuon in detail, you might  find this thread super
 * interesting: https://lkml.org/lkml/2004/10/6/117
 */
int rb_thread_fd_select(int nfds, rb_fdset_t *rfds, rb_fdset_t *wfds, rb_fdset_t *efds, struct timeval *timeout);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_SELECT_H */
