#ifndef RBIMPL_INTERN_SELECT_LARGESIZE_H             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SELECT_LARGESIZE_H
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
 *
 * Several Unix  platforms support file  descriptors bigger than  FD_SETSIZE in
 * `select(2)` system call.
 *
 * - Linux 2.2.12 (?)
 *
 * - NetBSD 1.2 (src/sys/kern/sys_generic.c:1.25)
 *   `select(2)` documents how to allocate fd_set dynamically.
 *   http://netbsd.gw.com/cgi-bin/man-cgi?select++NetBSD-4.0
 *
 * - FreeBSD 2.2 (src/sys/kern/sys_generic.c:1.19)
 *
 * - OpenBSD 2.0 (src/sys/kern/sys_generic.c:1.4)
 *   `select(2)` documents how to allocate fd_set dynamically.
 *   http://www.openbsd.org/cgi-bin/man.cgi?query=select&manpath=OpenBSD+4.4
 *
 * - HP-UX documents how to allocate fd_set dynamically.
 *   http://docs.hp.com/en/B2355-60105/select.2.html
 *
 * - Solaris 8 has `select_large_fdset`
 *
 * - Mac OS X 10.7 (Lion)
 *   `select(2)` returns `EINVAL`  if `nfds` is greater  than `FD_SET_SIZE` and
 *   `_DARWIN_UNLIMITED_SELECT` (or `_DARWIN_C_SOURCE`) isn't defined.
 *   http://developer.apple.com/library/mac/#releasenotes/Darwin/SymbolVariantsRelNotes/_index.html
 *
 * When `fd_set` is not  big enough to hold big file  descriptors, it should be
 * allocated dynamically.   Note that  this assumes  `fd_set` is  structured as
 * bitmap.
 *
 * `rb_fd_init` allocates the memory.
 * `rb_fd_term` frees the memory.
 * `rb_fd_set` may re-allocate bitmap.
 *
 * So `rb_fd_set` doesn't reject file descriptors bigger than `FD_SETSIZE`.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"

/**@cond INTERNAL_MACRO */
#define rb_fd_ptr rb_fd_ptr
#define rb_fd_max rb_fd_max
/** @endcond */

struct timeval;

/**
 * The data  structure which wraps the  fd_set bitmap used by  select(2).  This
 * allows Ruby to use FD sets  larger than that allowed by historic limitations
 * on modern platforms.
 */
typedef struct {
    int maxfd;                  /**< Maximum allowed number of FDs. */
    fd_set *fdset;              /**< File descriptors buffer */
} rb_fdset_t;

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_NONNULL(())
/**
 * (Re-)initialises a  fdset.  One must  be initialised before  other `rb_fd_*`
 * operations.  Analogous to calling `malloc(3)` to allocate an `fd_set`.
 *
 * @param[out]  f  An fdset to squash.
 * @post        `f` holds no file descriptors.
 */
void rb_fd_init(rb_fdset_t *f);

RBIMPL_ATTR_NONNULL(())
/**
 * Destroys the ::rb_fdset_t,  releasing any memory and resources  it used.  It
 * must be  reinitialised using rb_fd_init()  before future use.   Analogous to
 * calling `free(3)` to release memory for an `fd_set`.
 *
 * @param[out]  f  An fdset to squash.
 * @post        `f` holds no file descriptors.
 */
void rb_fd_term(rb_fdset_t *f);

RBIMPL_ATTR_NONNULL(())
/**
 * Wipes out the current set of FDs.
 *
 * @param[out]  f  The fdset to clear.
 * @post        `f` has no FDs.
 */
void rb_fd_zero(rb_fdset_t *f);

RBIMPL_ATTR_NONNULL(())
/**
 * Sets an fd to a fdset.
 *
 * @param[in]   fd  A file descriptor.
 * @param[out]  f   Target fdset.
 * @post        `f` holds `fd`.
 */
void rb_fd_set(int fd, rb_fdset_t *f);

RBIMPL_ATTR_NONNULL(())
/**
 * Releases a specific FD from the given fdset.
 *
 * @param[in]   fd  Target FD.
 * @param[out]  f   The fdset that holds `fd`.
 * @post        `f` doesn't hold n.
 */
void rb_fd_clr(int fd, rb_fdset_t *f);

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_PURE()
/**
 * Queries if the given FD is in the given set.
 *
 * @param[in]  fd  Target FD.
 * @param[in]  f   The fdset to scan.
 * @retval     1   Yes there is.
 * @retval     0   No there isn't.
 * @see        http://www.freebsd.org/cgi/query-pr.cgi?pr=91421
 */
int rb_fd_isset(int fd, const rb_fdset_t *f);

/**
 * Destructively overwrites an fdset with another.
 *
 * @param[out]  dst   Target fdset.
 * @param[in]   src   Source fdset.
 * @param[in]   max   Maximum number of file descriptors to copy.
 * @post        `dst` is a copy of `src`.
 */
void rb_fd_copy(rb_fdset_t *dst, const fd_set *src, int max);

/**
 * Identical  to  rb_fd_copy(),  except  it copies  unlimited  number  of  file
 * descriptors.
 *
 * @param[out]  dst   Target fdset.
 * @param[in]   src   Source fdset.
 * @post        `dst` is a copy of `src`.
 */
void rb_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);

/**
 * Waits for multiple file descriptors at once.
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
 */
int rb_fd_select(int nfds, rb_fdset_t *rfds, rb_fdset_t *wfds, rb_fdset_t *efds, struct timeval *timeout);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_PURE()
/**
 * Raw pointer to `fd_set`.
 *
 * @param[in]  f         Target fdset.
 * @retval     NULL      `f` is already terminated by rb_fd_term().
 * @retval     otherwise  Underlying fd_set.
 *
 * @internal
 *
 * Extension library  must not touch  raw pointers.  It was  a bad idea  to let
 * them use it.
 */
static inline fd_set *
rb_fd_ptr(const rb_fdset_t *f)
{
    return f->fdset;
}

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_PURE()
/**
 * It seems this function has no use.  Maybe just remove?
 *
 * @param[in]  f  A set.
 * @return     Number of file descriptors stored.
 */
static inline int
rb_fd_max(const rb_fdset_t *f)
{
    return f->maxfd;
}

#endif /* RBIMPL_INTERN_SELECT_LARGESIZE_H */
