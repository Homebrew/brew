#ifndef RBIMPL_INTERN_SELECT_POSIX_H                 /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SELECT_POSIX_H
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
 */
#include "ruby/internal/config.h"

#ifdef HAVE_SYS_SELECT_H
# include <sys/select.h>        /* for select(2) (modern POSIX) */
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>            /* for select(2) (archaic UNIX) */
#endif

#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"

/**
 * The data structure which wraps the  fd_set bitmap used by `select(2)`.  This
 * allows Ruby to use FD sets larger than what has been historically allowed on
 * modern platforms.
 *
 * @internal
 *
 * ... but because  this header file is  included only when the  system is with
 * that "historic restrictions", this is nothing more than an alias of fd_set.
 */
typedef fd_set rb_fdset_t;

/** Clears the given ::rb_fdset_t. */
#define rb_fd_zero   FD_ZERO

/** Sets the given fd to the ::rb_fdset_t. */
#define rb_fd_set    FD_SET

/** Unsets the given fd from the ::rb_fdset_t. */
#define rb_fd_clr    FD_CLR

/** Queries if the given fd is in the ::rb_fdset_t. */
#define rb_fd_isset  FD_ISSET

/** Initialises the :given :rb_fdset_t. */
#define rb_fd_init   FD_ZERO

/** Waits for multiple file descriptors at once. */
#define rb_fd_select select

/**@cond INTERNAL_MACRO */
#define rb_fd_copy  rb_fd_copy
#define rb_fd_dup   rb_fd_dup
#define rb_fd_ptr   rb_fd_ptr
#define rb_fd_max   rb_fd_max
/** @endcond */

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_NOALIAS()
/**
 * Destructively overwrites an fdset with another.
 *
 * @param[out]  dst   Target fdset.
 * @param[in]   src   Source fdset.
 * @param[in]   n     Unused parameter.
 * @post        `dst` is a copy of `src`.
 */
static inline void
rb_fd_copy(rb_fdset_t *dst, const fd_set *src, int n)
{
    *dst = *src;
}

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_NOALIAS()
/**
 * Destructively overwrites an fdset with another.
 *
 * @param[out]  dst   Target fdset.
 * @param[in]   src   Source fdset.
 * @post        `dst` is a copy of `src`.
 */
static inline void
rb_fd_dup(rb_fdset_t *dst, const fd_set *src)
{
    *dst = *src;
}

RBIMPL_ATTR_PURE()
/* :TODO: can this function be __attribute__((returns_nonnull)) or not? */
/**
 * Raw pointer to `fd_set`.
 *
 * @param[in]  f  Target fdset.
 * @return     Underlying fd_set.
 *
 * @internal
 *
 * Extension library  must not touch  raw pointers.  It was  a bad idea  to let
 * them use it.
 */
static inline fd_set *
rb_fd_ptr(rb_fdset_t *f)
{
    return f;
}

RBIMPL_ATTR_CONST()
/**
 * It seems this function has no use.  Maybe just remove?
 *
 * @param[in]  f  A set.
 * @return     Number of file descriptors stored.
 */
static inline int
rb_fd_max(const rb_fdset_t *f)
{
    return FD_SETSIZE;
}

/** @cond INTERNAL_MACRO */
/* :FIXME: What are these?  They don't exist for sibling implementations. */
#define rb_fd_init_copy(d, s) (*(d) = *(s))
#define rb_fd_term(f)   ((void)(f))
/** @endcond */

#endif /* RBIMPL_INTERN_SELECT_POSIX_H */
