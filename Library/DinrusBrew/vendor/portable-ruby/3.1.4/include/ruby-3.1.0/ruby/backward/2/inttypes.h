#ifndef RUBY_BACKWARD2_INTTYPES_H                    /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_BACKWARD2_INTTYPES_H
/**
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
 * @brief      C99 shim for `<inttypes.h>`
 */
#include "ruby/internal/config.h"      /* PRI_LL_PREFIX etc. are here */

#ifdef HAVE_INTTYPES_H
# include <inttypes.h>
#endif

#include "ruby/internal/value.h"       /* PRI_VALUE_PREFIX is here. */

#ifndef PRI_INT_PREFIX
# define PRI_INT_PREFIX ""
#endif

#ifndef PRI_LONG_PREFIX
# define PRI_LONG_PREFIX "l"
#endif

#ifndef PRI_SHORT_PREFIX
# define PRI_SHORT_PREFIX "h"
#endif

#ifdef PRI_64_PREFIX
# /* Take that. */
#elif SIZEOF_LONG == 8
# define PRI_64_PREFIX PRI_LONG_PREFIX
#elif SIZEOF_LONG_LONG == 8
# define PRI_64_PREFIX PRI_LL_PREFIX
#endif

#ifndef PRIdPTR
# define PRIdPTR PRI_PTR_PREFIX"d"
# define PRIiPTR PRI_PTR_PREFIX"i"
# define PRIoPTR PRI_PTR_PREFIX"o"
# define PRIuPTR PRI_PTR_PREFIX"u"
# define PRIxPTR PRI_PTR_PREFIX"x"
# define PRIXPTR PRI_PTR_PREFIX"X"
#endif

#ifndef RUBY_PRI_VALUE_MARK
# define RUBY_PRI_VALUE_MARK "\v"
#endif

#if defined PRIdPTR && !defined PRI_VALUE_PREFIX
# define PRIdVALUE PRIdPTR
# define PRIoVALUE PRIoPTR
# define PRIuVALUE PRIuPTR
# define PRIxVALUE PRIxPTR
# define PRIXVALUE PRIXPTR
# define PRIsVALUE PRIiPTR"" RUBY_PRI_VALUE_MARK
#else
# define PRIdVALUE PRI_VALUE_PREFIX"d"
# define PRIoVALUE PRI_VALUE_PREFIX"o"
# define PRIuVALUE PRI_VALUE_PREFIX"u"
# define PRIxVALUE PRI_VALUE_PREFIX"x"
# define PRIXVALUE PRI_VALUE_PREFIX"X"
# define PRIsVALUE PRI_VALUE_PREFIX"i" RUBY_PRI_VALUE_MARK
#endif

#ifndef PRI_VALUE_PREFIX
# define PRI_VALUE_PREFIX ""
#endif

#ifdef PRI_TIMET_PREFIX
# /* Take that. */
#elif SIZEOF_TIME_T == SIZEOF_INT
# define PRI_TIMET_PREFIX
#elif SIZEOF_TIME_T == SIZEOF_LONG
# define PRI_TIMET_PREFIX "l"
#elif SIZEOF_TIME_T == SIZEOF_LONG_LONG
# define PRI_TIMET_PREFIX PRI_LL_PREFIX
#endif

#ifdef PRI_PTRDIFF_PREFIX
# /* Take that. */
#elif SIZEOF_PTRDIFF_T == SIZEOF_INT
# define PRI_PTRDIFF_PREFIX ""
#elif SIZEOF_PTRDIFF_T == SIZEOF_LONG
# define PRI_PTRDIFF_PREFIX "l"
#elif SIZEOF_PTRDIFF_T == SIZEOF_LONG_LONG
# define PRI_PTRDIFF_PREFIX PRI_LL_PREFIX
#endif

#ifndef PRIdPTRDIFF
# define PRIdPTRDIFF PRI_PTRDIFF_PREFIX"d"
# define PRIiPTRDIFF PRI_PTRDIFF_PREFIX"i"
# define PRIoPTRDIFF PRI_PTRDIFF_PREFIX"o"
# define PRIuPTRDIFF PRI_PTRDIFF_PREFIX"u"
# define PRIxPTRDIFF PRI_PTRDIFF_PREFIX"x"
# define PRIXPTRDIFF PRI_PTRDIFF_PREFIX"X"
#endif

#ifdef PRI_SIZE_PREFIX
# /* Take that. */
#elif SIZEOF_SIZE_T == SIZEOF_INT
# define PRI_SIZE_PREFIX ""
#elif SIZEOF_SIZE_T == SIZEOF_LONG
# define PRI_SIZE_PREFIX "l"
#elif SIZEOF_SIZE_T == SIZEOF_LONG_LONG
# define PRI_SIZE_PREFIX PRI_LL_PREFIX
#endif

#ifndef PRIdSIZE
# define PRIdSIZE PRI_SIZE_PREFIX"d"
# define PRIiSIZE PRI_SIZE_PREFIX"i"
# define PRIoSIZE PRI_SIZE_PREFIX"o"
# define PRIuSIZE PRI_SIZE_PREFIX"u"
# define PRIxSIZE PRI_SIZE_PREFIX"x"
# define PRIXSIZE PRI_SIZE_PREFIX"X"
#endif

#endif /* RUBY_BACKWARD2_INTTYPES_H */
