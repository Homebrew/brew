#ifndef RUBY_UTIL_H                                  /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_UTIL_H 1
/**
 * @file
 * @author     $Author$
 * @date       Thu Mar  9 11:55:53 JST 1995
 * @copyright  Copyright (C) 1993-2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    DO NOT ADD RANDOM GARBAGES IN  THIS FILE!  Contents of this file
 *             reside here for historical reasons.  Find a right place for your
 *             API!
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>                       /* size_t */
#endif

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>                    /* ssize_t */
#endif

#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/nodiscard.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/restrict.h"
#include "ruby/internal/attr/returns_nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/defines.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/** an approximation of ceil(n * log10(2)), up to 1,048,576 (1<<20)
 * without overflow within 32-bit calculation
 */
#define DECIMAL_SIZE_OF_BITS(n) (((n) * 3010 + 9998) / 9999)

/** an approximation of decimal representation size for n-bytes */
#define DECIMAL_SIZE_OF_BYTES(n) DECIMAL_SIZE_OF_BITS((n) * CHAR_BIT)

/**
 * An approximation of decimal representation size. `expr` may be a
 * type name
 */
#define DECIMAL_SIZE_OF(expr) DECIMAL_SIZE_OF_BYTES(sizeof(expr))

/**
 * Character to  number mapping  like `'a'`  -> `10`, `'b'`  -> `11`  etc.  For
 * punctuation etc.,  the value is  -1.  "36"  terminology comes from  the fact
 * that this is the table behind `str.to_i(36)`.
 */
RUBY_EXTERN const signed char ruby_digit36_to_number_table[];

/**
 * Characters that Ruby accepts as hexadecimal digits.  This is `/\h/` expanded
 * into an array.
 */
RUBY_EXTERN const char ruby_hexdigits[];

/**
 * Scans the passed string, assuming the  string is a textual representation of
 * an  integer.  Stops  when encountering  something non-digit  for the  passed
 * base.
 *
 * @note        This does not understand minus sign.
 * @note        This does not understand e.g. `0x` prefix.
 * @note        It is a failure to pass `0` to `base`, unlike ruby_strtoul().
 * @param[in]   str       Target string of digits to interpret.
 * @param[in]   len       Number of bytes of `str`, or -1 to detect `NUL`.
 * @param[in]   base      Base, `2` to `36` inclusive.
 * @param[out]  retlen    Return value buffer.
 * @param[out]  overflow  Return value buffer.
 * @return      Interpreted numeric representation of `str`.
 * @post        `retlen` is the number of bytes scanned so far.
 * @post       `overflow` is  set to  true if  the string  represents something
 *              bigger than  `ULONG_MAX`.  Something meaningful  still returns;
 *              which is the designed belabour of C's unsigned arithmetic.
 */
unsigned long ruby_scan_digits(const char *str, ssize_t len, int base, size_t *retlen, int *overflow);

/** @old{ruby_scan_oct} */
#define scan_oct(s,l,e) ((int)ruby_scan_oct((s),(l),(e)))

RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL(())
/**
 * Interprets  the passed  string as  an  octal unsigned  integer.  Stops  when
 * encounters something not understood.
 *
 * @param[in]   str       C string to scan.
 * @param[in]   len       Length of `str`.
 * @param[out]  consumed  Return value buffer.
 * @return      Parsed integer.
 * @post        `ret` is the number of characters read.
 *
 * @internal
 *
 * No consideration  is made  for integer  overflows.  As  the return  value is
 * unsigned this function  has fully defined behaviour, but you  cannot know if
 * there was an integer wrap-around or not.
 */
unsigned long ruby_scan_oct(const char *str, size_t len, size_t *consumed);

/** @old{ruby_scan_hex} */
#define scan_hex(s,l,e) ((int)ruby_scan_hex((s),(l),(e)))

RBIMPL_ATTR_NONNULL(())
/**
 * Interprets the  passed string  a hexadecimal  unsigned integer.   Stops when
 * encounters something not understood.
 *
 * @param[in]   str  C string to scan.
 * @param[in]   len  Length of `str`.
 * @param[out]  ret  Return value buffer.
 * @return      Parsed integer.
 * @post        `ret` is the number of characters read.
 *
 * @internal
 *
 * No consideration  is made  for integer  overflows.  As  the return  value is
 * unsigned this function  has fully defined behaviour, but you  cannot know if
 * there was an integer wrap-around or not.
 */
unsigned long ruby_scan_hex(const char *str, size_t len, size_t *ret);

/**
 * Reentrant implementation of  quick sort.  If your  system provides something
 * (like  C11 qsort_s),  this is  a thin  wrapper of  that routine.   Otherwise
 * resorts to our own version.
 */
#ifdef HAVE_GNU_QSORT_R
# define ruby_qsort qsort_r
#else
void ruby_qsort(void *, const size_t, const size_t,
                int (*)(const void *, const void *, void *), void *);
#endif

RBIMPL_ATTR_NONNULL((1))
/**
 * Sets  an environment  variable.   In case  of  POSIX this  is  a wrapper  of
 * `setenv(3)`.  But there are systems which lack one.  We try hard emulating.
 *
 * @param[in]  key                  An environment variable.
 * @param[in]  val                  A value to be associated with `key`, or 0.
 * @exception  rb_eSystemCallError  `setenv(3)` failed for some reason.
 * @post       Environment variable  `key` is created if  necessary.  Its value
 *             is updated to be `val`.
 */
void ruby_setenv(const char *key, const char *val);

RBIMPL_ATTR_NONNULL(())
/**
 * Deletes the passed environment variable, if any.
 *
 * @param[in]  key                  An environment variable.
 * @exception  rb_eSystemCallError  `unsetenv(3)` failed for some reason.
 * @post       Environment variable `key` does not exist.
 */
void ruby_unsetenv(const char *key);

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_NONNULL(())
/**
 * This is our  own version of `strdup(3)` that uses  ruby_xmalloc() instead of
 * system malloc (benefits our GC).
 *
 * @param[in]  str  Target C string to duplicate.
 * @return     An allocated C string holding the identical contents.
 * @note       Return value must be discarded using ruby_xfree().
 */
char *ruby_strdup(const char *str);

#undef strdup
/**
 * @alias{ruby_strdup}
 *
 * @internal
 *
 * @shyouhei doesn't  think it  is a wise  idea.  ruby_strdup()'s  return value
 * must be passed to ruby_xfree(), but this macro makes it almost impossible.
 */
#define strdup(s) ruby_strdup(s)

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
/**
 * This is our  own version of `getcwd(3)` that uses  ruby_xmalloc() instead of
 * system malloc (benefits our GC).
 *
 * @return     An allocated C string holding the process working directory.
 * @note       Return value must be discarded using ruby_xfree().
 */
char *ruby_getcwd(void);

RBIMPL_ATTR_NONNULL((1))
/**
 * Our own locale-insensitive  version of `strtod(3)`.  The  conversion is done
 * as if the current locale is set  to the "C" locale, no matter actual runtime
 * locale settings.
 *
 * @param[in]   str     Decimal  or hexadecimal  representation  of a  floating
 *                      point number.
 * @param[out]  endptr  NULL, or an arbitrary pointer (overwritten on return).
 * @return      Converted number.
 * @post        If `endptr` is not NULL, it  is updated to point the first such
 *              byte where conversion failed.
 * @note        This function sets `errno` on failure.
 *                - `ERANGE`: Converted integer is out of range of `double`.
 * @see         William  D.   Clinger,  "How  to Read  Floating  Point  Numbers
 *              Accurately" in Proc.  ACM SIGPLAN '90, pp.  92-101.
 *              https://doi.org/10.1145/93542.93557
 */
double ruby_strtod(const char *str, char **endptr);

#undef strtod
/** @alias{ruby_strtod} */
#define strtod(s,e) ruby_strtod((s),(e))

RBIMPL_ATTR_NONNULL((2))
/**
 * Scans the  passed string, with calling  the callback function every  time it
 * encounters a  "word".  A word  here is a  series of characters  separated by
 * either a space (of IEEE 1003.1 section 7.3.1.1), or a `','`.
 *
 * @param[in]      str   Target string to split into each words.
 * @param[in]      func  Callback function.
 * @param[in,out]  argv  Passed as-is to `func`.
 */
void ruby_each_words(const char *str, void (*func)(const char *word, int len, void *argv), void *argv);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_UTIL_H */
