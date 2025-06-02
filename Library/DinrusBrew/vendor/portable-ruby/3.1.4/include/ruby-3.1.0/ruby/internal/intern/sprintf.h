#ifndef RBIMPL_INTERN_SPRINTF_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SPRINTF_H
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
 * @brief      Our own private `printf(3)`.
 */
#include "ruby/internal/attr/format.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* sprintf.c */

/**
 * Identical to rb_str_format(), except how the arguments are arranged.
 *
 * @param[in]  argc  Number of objects of `argv`.
 * @param[in]  argv  A format string, followed by its arguments.
 * @return     A rendered new instance of ::rb_cString.
 *
 * @internal
 *
 * You can safely pass NULL to `argv`.  Doesn't make any sense though.
 */
VALUE rb_f_sprintf(int argc, const VALUE *argv);

RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 2)
/**
 * Ruby's extended `sprintf(3)`.   We ended up reinventing  the entire `printf`
 * business because we  don't want to depend on  locales.  OS-provided `printf`
 * routines  might or  might  not,  which caused  instabilities  of the  result
 * strings.
 *
 * The format  sequence is a  mixture of  format specifiers and  other verbatim
 * contents.  Each  format specifier starts with  a `%`, and has  the following
 * structure:
 *
 * ```
 * %[flags][width][.precision][length]conversion
 * ```
 *
 * This  function  supports  flags  of   ` `, `#`,  `+`,  `-`,  `0`,  width  of
 * non-negative  decimal integer  and  `*`, precision  of non-negative  decimal
 * integers and `*`, length of `L`,  `h`, `t`, `z`, `l`, `ll`, `q`, conversions
 * of `A`,  `D`, `E`, `G`, `O`,  `U`, `X`, `a`,  `c`, `d`, `e`, `f`,  `g`, `i`,
 * `n`, `o`, `p`, `s`, `u`, `x`, and `%`.  In case of `_WIN32` it also supports
 * `I`.   And additionally,  it  supports magical  `PRIsVALUE`  macro that  can
 * stringise arbitrary Ruby objects:
 *
 * ```CXX
 * rb_sprintf("|%"PRIsVALUE"|", RUBY_Qtrue); // => "|true|"
 * rb_sprintf("%+"PRIsVALUE, rb_stdin);      // => "#<IO:<STDIN>>"
 * ```
 *
 * @param[in]  fmt  A `printf`-like format specifier.
 * @param[in]  ...  Variadic number of contents to format.
 * @return     A rendered new instance of ::rb_cString.
 *
 * @internal
 *
 * :FIXME:  We can improve this document.
 */
VALUE rb_sprintf(const char *fmt, ...);

RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 0)
/**
 * Identical to rb_sprintf(), except it takes a `va_list`.
 *
 * @param[in]  fmt  A `printf`-like format specifier.
 * @param[in]  ap   Contents to format.
 * @return     A rendered new instance of ::rb_cString.
 */
VALUE rb_vsprintf(const char *fmt, va_list ap);

RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Identical to  rb_sprintf(), except  it renders the  output to  the specified
 * object rather than creating a new one.
 *
 * @param[out]  dst            String to modify.
 * @param[in]   fmt            A `printf`-like format specifier.
 * @param[in]   ...            Variadic number of contents to format.
 * @exception   rb_eTypeError  `dst` is not a String.
 * @return      Passed `dst`.
 * @post        `dst` has the rendered output appended to its end.
 */
VALUE rb_str_catf(VALUE dst, const char *fmt, ...);

RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 0)
/**
 * Identical to  rb_str_catf(), except it  takes a  `va_list`.  It can  also be
 * seen as a  routine identical to rb_vsprintf(), except it  renders the output
 * to the specified object rather than creating a new one.
 *
 * @param[out]  dst            String to modify.
 * @param[in]   fmt            A `printf`-like format specifier.
 * @param[in]   ap             Contents to format.
 * @exception   rb_eTypeError  `dst` is not a String.
 * @return      Passed `dst`.
 * @post        `dst` has the rendered output appended to its end.
 */
VALUE rb_str_vcatf(VALUE dst, const char *fmt, va_list ap);

/**
 * Formats a string.
 *
 * Returns  the string  resulting from  applying `fmt`  to `argv`.   The format
 * sequence  is a  mixture of  format specifiers  and other  verbatim contents.
 * Each format specifier starts with a `%`, and has the following structure:
 *
 * ```
 * %[flags][width][.precision]type
 * ```
 *
 * ...  which is  different from  that of  rb_sprintf().  Because  ruby has  no
 * `short` or `long`, there is no way to specify a "length" of an argument.
 *
 * This function  supports flags  of ` `,  `#`, `+`, `-`,  `<>`, `{}`,  with of
 * non-negative decimal integer and `$`, `*`, precision of non-negative decimal
 * integer and `$`, `*`,  type of `A`, `B`, `E`, `G`, `X`,  `a`, `b`, `c`, `d`,
 * `e`,  `f`, `g`,  `i`, `o`,  `p`,  `s`, `u`,  `x`,  `%`.  This  list is  also
 * (largely the same but) not identical to that of rb_sprintf().
 *
 * @param[in]  argc           Number of objects in `argv`.
 * @param[in]  argv           Format arguments.
 * @param[in]  fmt            A printf-like format specifier.
 * @exception  rb_eTypeError  `fmt` is not a string.
 * @exception  rb_eArgError   Failed to parse `fmt`.
 * @return     A rendered new instance of ::rb_cString.
 * @note       Everything it takes must be Ruby objects.
 *
 */
VALUE rb_str_format(int argc, const VALUE *argv, VALUE fmt);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_SPRINTF_H */
