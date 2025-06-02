#ifndef RBIMPL_INTERN_RE_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_RE_H
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
 * @brief      Public APIs related to ::rb_cRegexp.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* re.c */

/**
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 *
 * @internal
 *
 * This was a  function that switched between memcmp  and rb_memcicmp depending
 * on then-called `ruby_ignorecase`, or the `$=` global variable.  That feature
 * was abandoned in sometime around version 1.9.0.
 */
#define rb_memcmp memcmp

/**
 * Identical to  st_locale_insensitive_strcasecmp(), except  it is  timing safe
 * and returns something different.
 *
 * @param[in]  s1  Comparison LHS.
 * @param[in]  s2  Comparison RHS.
 * @param[in]  n   Comparison shall stop after first `n` bytes are scanned.
 * @retval     <0  `s1` is "less" than `s2`.
 * @retval      0  Both sides converted into lowercase would be identical.
 * @retval     >0  `s1` is "greater" than `s2`.
 * @note       The "case" here means that of the POSIX Locale.
 *
 * @internal
 *
 * Can accept NULLs as long as n is also 0, and returns 0.
 */
int rb_memcicmp(const void *s1,const void *s2, long n);

/**
 * Asserts  that  the given  MatchData  is  "occupied".  MatchData  shares  its
 * backend storages  with its  Regexp object.   But programs  can destructively
 * tamper its  contents.  Calling this  function beforehand shall  prevent such
 * modifications to spill over into other objects.
 *
 * @param[out]  md  Target instance of ::rb_cMatch.
 * @post        The object is "busy".
 *
 * @internal
 *
 * There is rb_match_unbusy internally, but extension libraries are left unable
 * to do so.
 */
void rb_match_busy(VALUE md);

/**
 * Identical to rb_reg_nth_match(), except it just returns Boolean.  This could
 * skip allocating a  returning string, resulting in  reduced memory footprints
 * if applicable.
 *
 * @param[in]  n              Match index.
 * @param[in]  md             An instance of ::rb_cMatch.
 * @exception  rb_eTypeError  `md` is not initialised.
 * @retval     RUBY_Qnil      There is no `n`-th capture.
 * @retval     RUBY_Qfalse    There is a `n`-th capture and is empty.
 * @retval     RUBY_Qtrue     There is a `n`-th capture that has something.
 *
 */
VALUE rb_reg_nth_defined(int n, VALUE md);

/**
 * Queries the nth captured substring.
 *
 * @param[in]  n              Match index.
 * @param[in]  md             An instance of ::rb_cMatch.
 * @exception  rb_eTypeError  `md` is not initialised.
 * @retval     RUBY_Qnil      There is no `n`-th capture.
 * @retval     otherwise      An allocated instance of  ::rb_cString containing
 *                            the contents captured.
 */
VALUE rb_reg_nth_match(int n, VALUE md);

/**
 * Queries the index of the given named capture.  Captures could be named.  But
 * that doesn't mean named ones are  not indexed.  A regular expression can mix
 * named  and non-named  captures, and  they  are all  indexed.  This  function
 * converts from a name to its index.
 *
 * @param[in]  match           An instance of ::rb_cMatch.
 * @param[in]  backref         Capture name, in String, Symbol, or Numeric.
 * @exception  rb_eIndexError  No such named capture.
 * @return     The index of the given name.
 */
int rb_reg_backref_number(VALUE match, VALUE backref);

/**
 * This just returns the argument, stringified.  What a poor name.
 *
 * @param[in]  md  An instance of ::rb_cMatch.
 * @return     Its 0th capture (i.e. entire matched string).
 */
VALUE rb_reg_last_match(VALUE md);

/**
 * The portion of the original string before the given match.
 *
 * @param[in]  md  An instance of ::rb_cMatch.
 * @return     Its "prematch".  This is perl's ``$```.
 */
VALUE rb_reg_match_pre(VALUE md);

/**
 * The portion of the original string after the given match.
 *
 * @param[in]  md  An instance of ::rb_cMatch.
 * @return     Its "postmatch".  This is perl's `$'`.
 */
VALUE rb_reg_match_post(VALUE md);

/**
 * The portion of the original string that captured at the very last.
 *
 * @param[in]  md  An instance of ::rb_cMatch.
 * @return     Its "lastmatch".  This is perl's `$+`.
 */
VALUE rb_reg_match_last(VALUE md);

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define HAVE_RB_REG_NEW_STR 1

/**
 * Identical to rb_reg_new(),  except it takes the expression  in Ruby's string
 * instead of C's.
 *
 * @param[in]  src              Source code in String.
 * @param[in]  opts             Options e.g. ONIG_OPTION_MULTILINE.
 * @exception  rb_eRegexpError  `src` and `opts` do not interface.
 * @return     Allocated new instance of ::rb_cRegexp.
 */
VALUE rb_reg_new_str(VALUE src, int opts);

RBIMPL_ATTR_NONNULL(())
/**
 * Creates a new Regular expression.
 *
 * @param[in]  src              Source code.
 * @param[in]  len              `strlen(src)`.
 * @param[in]  opts             Options e.g. ONIG_OPTION_MULTILINE.
 * @return     Allocated new instance of ::rb_cRegexp.
 */
VALUE rb_reg_new(const char *src, long len, int opts);

/**
 * Allocates an instance of ::rb_cRegexp.
 *
 * @private
 *
 * Nobody  should  call  this  function.   Regular  expressions  that  are  not
 * initialised must not exist in the wild.
 */
VALUE rb_reg_alloc(void);

/**
 * Initialises an instance of ::rb_cRegexp.
 *
 * @private
 *
 * This just raises  for ordinal regexp objects.  Extension  libraries must not
 * use.
 */
VALUE rb_reg_init_str(VALUE re, VALUE s, int options);

/**
 * This is the match operator.
 *
 * @param[in]  re               An instance of ::rb_cRegexp.
 * @param[in]  str              An instance of ::rb_cString.
 * @exception  rb_eTypeError    `str` is not a string.
 * @exception  rb_eRegexpError  Error inside of Onigmo (unlikely).
 * @retval     RUBY_Qnil        Match failed.
 * @retval     otherwise        Matched  position  (character index  inside  of
 *                              `str`).
 * @post       `Regexp.last_match` is updated.
 * @post       `$&`, `$~`, etc., are updated.
 * @note       If you  do this in  ruby, named  captures are assigned  to local
 *             variable of the local scope.  But that doesn't happen here.  The
 *             assignment is done by the interpreter.
 */
VALUE rb_reg_match(VALUE re, VALUE str);

/**
 * Identical  to rb_reg_match(),  except it  matches against  rb_lastline_get()
 * (or, the `$_`).
 *
 * @param[in]  re               An instance of ::rb_cRegexp.
 * @exception  rb_eRegexpError  Error inside of Onigmo (unlikely).
 * @retval     RUBY_Qnil        Match failed or `$_` is absent.
 * @retval     otherwise        Matched  position  (character index  inside  of
 *                              `$_`).
 * @post       `Regexp.last_match` is updated.
 * @post       `$&`, `$~`, etc., are updated.
 */
VALUE rb_reg_match2(VALUE re);

/**
 * Queries the options of the passed regular expression.
 *
 * @param[in]  re  An instance of ::rb_cRegexp.
 * @return     Its options.
 * @note       Possible return values are defined in Onigmo.h.
 */
int rb_reg_options(VALUE re);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_RE_H */
