#ifndef RUBY_MISSING_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_MISSING_H 1
/**
 * @author     $Author$
 * @date       Sat May 11 23:46:03 JST 2002
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Prototype for *.c in ./missing, and for missing timeval struct.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#if defined(__cplusplus)
# include <cmath>
#else
# include <math.h> /* for INFINITY and NAN */
#endif

#ifdef RUBY_ALTERNATIVE_MALLOC_HEADER
# include RUBY_ALTERNATIVE_MALLOC_HEADER
#endif

#if defined(HAVE_TIME_H)
# include <time.h>
#endif

#if defined(HAVE_SYS_TIME_H)
# include <sys/time.h>
#endif

#ifdef HAVE_IEEEFP_H
# include <ieeefp.h>
#endif

#include "ruby/internal/dllexport.h"
#include "ruby/internal/attr/format.h"

#ifndef M_PI
# define M_PI 3.14159265358979323846
#endif
#ifndef M_PI_2
# define M_PI_2 (M_PI/2)
#endif

#if !defined(HAVE_STRUCT_TIMEVAL)
struct timeval {
    time_t tv_sec;	/* seconds */
    long tv_usec;	/* microseconds */
};
#endif /* HAVE_STRUCT_TIMEVAL */

#if !defined(HAVE_STRUCT_TIMESPEC)
/* :BEWARE: @shyouhei warns that  IT IS A WRONG IDEA to  define our own version
 * of struct timespec here.  `clock_gettime` is  a system call, and your kernel
 * could expect  something other  than just `long`  (results stack  smashing if
 * that happens).  See also https://ewontfix.com/19/ */
struct timespec {
    time_t tv_sec;	/* seconds */
    long tv_nsec;	/* nanoseconds */
};
#endif

#if !defined(HAVE_STRUCT_TIMEZONE)
struct timezone {
    int tz_minuteswest;
    int tz_dsttime;
};
#endif

RBIMPL_SYMBOL_EXPORT_BEGIN()

#ifndef HAVE_ACOSH
RUBY_EXTERN double acosh(double);
RUBY_EXTERN double asinh(double);
RUBY_EXTERN double atanh(double);
#endif

#ifndef HAVE_CRYPT
RUBY_EXTERN char *crypt(const char *, const char *);
#endif

#ifndef HAVE_EACCESS
RUBY_EXTERN int eaccess(const char*, int);
#endif

#ifndef HAVE_ROUND
RUBY_EXTERN double round(double);	/* numeric.c */
#endif

#ifndef HAVE_FLOCK
RUBY_EXTERN int flock(int, int);
#endif

/*
#ifndef HAVE_FREXP
RUBY_EXTERN double frexp(double, int *);
#endif
*/

#ifndef HAVE_HYPOT
RUBY_EXTERN double hypot(double, double);
#endif

#ifndef HAVE_ERF
RUBY_EXTERN double erf(double);
RUBY_EXTERN double erfc(double);
#endif

#ifndef HAVE_TGAMMA
RUBY_EXTERN double tgamma(double);
#endif

#ifndef HAVE_LGAMMA_R
RUBY_EXTERN double lgamma_r(double, int *);
#endif

#ifndef HAVE_CBRT
RUBY_EXTERN double cbrt(double);
#endif

#if !defined(INFINITY) || !defined(NAN)
union bytesequence4_or_float {
  unsigned char bytesequence[4];
  float float_value;
};
#endif

#ifndef INFINITY
/** @internal */
RUBY_EXTERN const union bytesequence4_or_float rb_infinity;
# define INFINITY (rb_infinity.float_value)
# define USE_RB_INFINITY 1
#endif

#ifndef NAN
/** @internal */
RUBY_EXTERN const union bytesequence4_or_float rb_nan;
# define NAN (rb_nan.float_value)
# define USE_RB_NAN 1
#endif

#ifndef HUGE_VAL
# define HUGE_VAL ((double)INFINITY)
#endif

#ifndef HAVE_FINITE
# define HAVE_FINITE 1
# define finite(x) isfinite(x)
#endif

#ifndef HAVE_NAN
RUBY_EXTERN double nan(const char *);
#endif

#ifndef HAVE_NEXTAFTER
RUBY_EXTERN double nextafter(double x, double y);
#endif

/*
#ifndef HAVE_MEMCMP
RUBY_EXTERN int memcmp(const void *, const void *, size_t);
#endif
*/

#ifndef HAVE_MEMMOVE
RUBY_EXTERN void *memmove(void *, const void *, size_t);
#endif

/*
#ifndef HAVE_MODF
RUBY_EXTERN double modf(double, double *);
#endif
*/

#ifndef HAVE_STRCHR
RUBY_EXTERN char *strchr(const char *, int);
RUBY_EXTERN char *strrchr(const char *, int);
#endif

#ifndef HAVE_STRERROR
RUBY_EXTERN char *strerror(int);
#endif

#ifndef HAVE_STRSTR
RUBY_EXTERN char *strstr(const char *, const char *);
#endif

#ifndef HAVE_STRLCPY
RUBY_EXTERN size_t strlcpy(char *, const char*, size_t);
#endif

#ifndef HAVE_STRLCAT
RUBY_EXTERN size_t strlcat(char *, const char*, size_t);
#endif

#ifndef HAVE_FFS
RUBY_EXTERN int ffs(int);
#endif

#ifdef BROKEN_CLOSE
# include <sys/types.h>
# include <sys/socket.h>
RUBY_EXTERN int ruby_getpeername(int, struct sockaddr *, socklen_t *);
RUBY_EXTERN int ruby_getsockname(int, struct sockaddr *, socklen_t *);
RUBY_EXTERN int ruby_shutdown(int, int);
RUBY_EXTERN int ruby_close(int);
#endif

#ifndef HAVE_SETPROCTITLE
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 2)
RUBY_EXTERN void setproctitle(const char *fmt, ...);
#endif

#ifdef HAVE_EXPLICIT_BZERO
# /* Take that. */
#elif defined(SecureZeroMemory)
# define explicit_bzero(b, len) SecureZeroMemory(b, len)
#else
RUBY_EXTERN void explicit_bzero(void *b, size_t len);
#endif

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_MISSING_H */
