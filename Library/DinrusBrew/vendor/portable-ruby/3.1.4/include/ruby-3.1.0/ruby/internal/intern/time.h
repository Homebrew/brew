#ifndef RBIMPL_INTERN_TIME_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_TIME_H
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
 * @brief      Public APIs related to ::rb_cTime.
 */
#include "ruby/internal/config.h"

#ifdef HAVE_TIME_H
# include <time.h>              /* for time_t */
#endif

#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

struct timespec;
struct timeval;

/* time.c */

RBIMPL_ATTR_NONNULL(())
/**
 * Fills the current time into the given struct.
 *
 * @param[out]  ts                   Return buffer.
 * @exception   rb_eSystemCallError  Access denied for hardware clock.
 * @post        Current time is stored in `*ts`.
 */
void rb_timespec_now(struct timespec *ts);

/**
 * Creates  an  instance of  ::rb_cTime  with  the  given  time and  the  local
 * timezone.
 *
 * @param[in]  sec             Seconds since the UNIX epoch.
 * @param[in]  usec            Subsecond part, in microseconds resolution.
 * @exception  rb_eRangeError  Cannot express the time.
 * @return     An allocated instance of ::rb_cTime.
 */
VALUE rb_time_new(time_t sec, long usec);

/**
 * Identical  to  rb_time_new(), except  it  accepts  the time  in  nanoseconds
 * resolution.
 *
 * @param[in]  sec             Seconds since the UNIX epoch.
 * @param[in]  nsec            Subsecond part, in nanoseconds resolution.
 * @exception  rb_eRangeError  Cannot express the time.
 * @return     An allocated instance of ::rb_cTime.
 */
VALUE rb_time_nano_new(time_t sec, long nsec);

RBIMPL_ATTR_NONNULL(())
/**
 * Creates an instance of ::rb_cTime, with given time and offset.
 *
 * @param[in]  ts            Time specifier.
 * @param[in]  offset        Offset specifier, can take following values:
 *                           - `INT_MAX`: `ts` is in local time.
 *                           - `INT_MAX - 1`: `ts` is in UTC.
 *                           - `-86400` to `86400`: fixed timezone.
 * @exception  rb_eArgError  Malformed `offset`.
 * @return     An allocated instance of ::rb_cTime.
 */
VALUE rb_time_timespec_new(const struct timespec *ts, int offset);

/**
 * Identical to rb_time_timespec_new(), except it  takes Ruby values instead of
 * C structs.
 *
 * @param[in]  timev         Something numeric.  Currently Integers, Rationals,
 *                           and Floats are accepted.
 * @param[in]  off           Offset  specifier.  As  of  2.7  this argument  is
 *                           heavily  extended  to   take  following  kinds  of
 *                           objects:
 *                             - ::RUBY_Qundef ... means UTC.
 *                             - ::rb_cString ... "+12:34" etc.
 *                             - A mysterious  "zone" object.  This  is largely
 *                               undocumented.  However the  initial intent was
 *                               that       we       want       to       accept
 *                               `ActiveSupport::TimeZone`  here.   Other  gems
 *                               could also be possible...   But how to make an
 *                               acceptable class is beyond this document.
 * @exception  rb_eArgError  Malformed `off`.
 * @return     An allocated instance of ::rb_cTime.
 */
VALUE rb_time_num_new(VALUE timev, VALUE off);

/**
 * Creates  a  "time  interval".   This   basically  converts  an  instance  of
 * ::rb_cNumeric  into  a struct  `timeval`,  but  for instance  negative  time
 * interval must not exist.
 *
 * @param[in]  num             An instance of ::rb_cNumeric.
 * @exception  rb_eArgError    `num` is negative.
 * @exception  rb_eRangeError  `num` is out of range of `timeval::tv_sec`.
 * @return     A struct that represents the identical time to `num`.
 */
struct timeval rb_time_interval(VALUE num);

/**
 * Converts an  instance of rb_cTime  to a  struct timeval that  represents the
 * identical point of time.  It can also take something numeric; would consider
 * it as a UNIX time then.
 *
 * @param[in]  time            Instance of either ::rb_cTime or ::rb_cNumeric.
 * @exception  rb_eRangeError  `time` is out of range of `timeval::tv_sec`.
 * @return     A struct that represents the identical time to `num`.
 */
struct timeval rb_time_timeval(VALUE time);

/**
 * Identical to rb_time_timeval(), except for return type.
 *
 * @param[in]  time            Instance of either ::rb_cTime or ::rb_cNumeric.
 * @exception  rb_eRangeError  `time` is out of range of `timeval::tv_sec`.
 * @return     A struct that represents the identical time to `num`.
 */
struct timespec rb_time_timespec(VALUE time);

/**
 * Identical to rb_time_interval(), except for return type.
 *
 * @param[in]  num             An instance of ::rb_cNumeric.
 * @exception  rb_eArgError    `num` is negative.
 * @exception  rb_eRangeError  `num` is out of range of `timespec::tv_sec`.
 * @return     A struct that represents the identical time to `num`.
 */
struct timespec rb_time_timespec_interval(VALUE num);

/**
 * Queries the  offset, in seconds  between the time zone  of the time  and the
 * UTC.
 *
 * @param[in]  time  An instance of ::rb_cTime.
 * @return     Numeric offset.
 */
VALUE rb_time_utc_offset(VALUE time);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_TIME_H */
