#ifndef RBIMPL_CTYPE_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_CTYPE_H
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
 * @brief      Our own, locale independent, character handling routines.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <ctype.h>
#endif

#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"

/**
 * @name Old character classification macros
 *
 * What  is this  #ISPRINT  business?   Well, according  to  our  VCS and  some
 * internet surfing, it appears that the initial intent of these macros were to
 * mimic codes appear  in common in several GNU projects.   As far as @shyouhei
 * detects they  seem to originate GNU  regex (that standalone one  rather than
 * Gnulib or Glibc), and at least date back to 1995.
 *
 * Let me lawfully quote from a GNU coreutils commit
 * https://git.savannah.gnu.org/cgit/coreutils.git/commit/?id=49803907f5dbd7646184a8912c9db9b09dcd0f22
 *
 *   > Jim Meyering writes:
 *   >
 *   > "... Some ctype macros are valid only for character codes that
 *   > isascii says are ASCII (SGI's IRIX-4.0.5 is one such system --when
 *   > using /bin/cc or gcc but without giving an ansi option).  So, all
 *   > ctype uses should be through macros like ISPRINT...  If
 *   > STDC_HEADERS is defined, then autoconf has verified that the ctype
 *   > macros don't need to be guarded with references to isascii. ...
 *   > Defining isascii to 1 should let any compiler worth its salt
 *   > eliminate the && through constant folding."
 *   >
 *   > Bruno Haible adds:
 *   >
 *   > "... Furthermore, isupper(c) etc. have an undefined result if c is
 *   > outside the range -1 <= c <= 255. One is tempted to write isupper(c)
 *   > with c being of type `char', but this is wrong if c is an 8-bit
 *   > character >= 128 which gets sign-extended to a negative value.
 *   > The macro ISUPPER protects against this as well."
 *
 * So the intent  was to reroute old problematic systems  that no longer exist.
 * At the same time the problems described  above no longer hurt us, because we
 * decided to completely  avoid using system-provided isupper  etc. to reinvent
 * the wheel.  These macros are entirely legacy; please ignore them.
 *
 * But let me also  put stress that GNU people are wise;  they use those macros
 * only inside of  their own implementations and never let  them be public.  On
 * the other hand ruby has thoughtlessly publicised them to 3rd party libraries
 * since its beginning, which is a very bad idea.  These macros are too easy to
 * get conflicted with definitions elsewhere.
 *
 * New programs should stick to the `rb_` prefixed names.
 *
 * @note  It seems we just mimic the API.  We do not share their implementation
 *        with GPL-ed programs.
 *
 * @{
 */
#ifndef ISPRINT
# define ISASCII  rb_isascii    /**< @old{rb_isascii}*/
# define ISPRINT  rb_isprint    /**< @old{rb_isprint}*/
# define ISGRAPH  rb_isgraph    /**< @old{rb_isgraph}*/
# define ISSPACE  rb_isspace    /**< @old{rb_isspace}*/
# define ISUPPER  rb_isupper    /**< @old{rb_isupper}*/
# define ISLOWER  rb_islower    /**< @old{rb_islower}*/
# define ISALNUM  rb_isalnum    /**< @old{rb_isalnum}*/
# define ISALPHA  rb_isalpha    /**< @old{rb_isalpha}*/
# define ISDIGIT  rb_isdigit    /**< @old{rb_isdigit}*/
# define ISXDIGIT rb_isxdigit   /**< @old{rb_isxdigit}*/
# define ISBLANK  rb_isblank    /**< @old{rb_isblank}*/
# define ISCNTRL  rb_iscntrl    /**< @old{rb_iscntrl}*/
# define ISPUNCT  rb_ispunct    /**< @old{rb_ispunct}*/
#endif

#define TOUPPER     rb_toupper    /**< @old{rb_toupper}*/
#define TOLOWER     rb_tolower    /**< @old{rb_tolower}*/
#define STRCASECMP  st_locale_insensitive_strcasecmp  /**< @old{st_locale_insensitive_strcasecmp}*/
#define STRNCASECMP st_locale_insensitive_strncasecmp /**< @old{st_locale_insensitive_strncasecmp}*/
#define STRTOUL     ruby_strtoul  /**< @old{ruby_strtoul}*/

/** @} */

RBIMPL_SYMBOL_EXPORT_BEGIN()
/** @name locale insensitive functions
 *  @{
 */

/* In descriptions below, `the POSIX Locale` and `the "C" locale` are tactfully
 * used as to whether the described function mimics POSIX or C99. */

RBIMPL_ATTR_NONNULL(())
/**
 * Our  own locale-insensitive  version  of `strcasecmp(3)`.   The "case"  here
 * always means that of the POSIX  Locale.  It doesn't depend on runtime locale
 * settings.
 *
 * @param[in]  s1  Comparison LHS.
 * @param[in]  s2  Comparison RHS.
 * @retval     -1  `s1` is "less" than `s2`.
 * @retval      0  Both strings converted into lowercase would be identical.
 * @retval      1  `s1` is "greater" than `s2`.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 */
int st_locale_insensitive_strcasecmp(const char *s1, const char *s2);

RBIMPL_ATTR_NONNULL(())
/**
 * Our  own locale-insensitive  version of  `strcnasecmp(3)`.  The  "case" here
 * always means that of the POSIX  Locale.  It doesn't depend on runtime locale
 * settings.
 *
 * @param[in]  s1  Comparison LHS.
 * @param[in]  s2  Comparison RHS.
 * @param[in]  n   Comparison shall stop after first `n` bytes are scanned.
 * @retval     -1  `s1` is "less" than `s2`.
 * @retval      0  Both strings converted into lowercase would be identical.
 * @retval      1  `s1` is "greater" than `s2`.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    This function is _not_ timing safe.
 */
int st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n);

RBIMPL_ATTR_NONNULL((1))
/**
 * Our own locale-insensitive version of  `strtoul(3)`.  The conversion is done
 * as if the current locale is set  to the "C" locale, no matter actual runtime
 * locale settings.
 *
 * @note        This is needed because  `strtoul("i", 0, 36)` would return zero
 *              if it is locale sensitive and the current locale is `tr_TR`.
 * @param[in]   str     String of digits,  optionally preceded with whitespaces
 *                      (ignored) and optionally `+` or `-` sign.
 * @param[out]  endptr  NULL, or an arbitrary pointer (overwritten on return).
 * @param[in]   base    `2` to  `36` inclusive for  each base, or  special case
 *                      `0` to detect the base from the contents of the string.
 * @return      Converted integer, casted to unsigned long.
 * @post        If `endptr` is not NULL, it  is updated to point the first such
 *              byte where conversion failed.
 * @note        This function sets `errno` on failure.
 *                - `EINVAL`: Passed `base` is out of range.
 *                - `ERANGE`: Converted integer is out of range of `long`.
 * @warning     As far as @shyouhei reads ISO/IEC 9899:2018 section 7.22.1.4, a
 *              conforming  `strtoul`  implementation   shall  render  `ERANGE`
 *              whenever  it  finds  the  input string  represents  a  negative
 *              integer.  Such thing can never be representable using `unsigned
 *              long`.   However  this  implementation  does  not  honour  that
 *              language.   It just  casts such  negative value  to the  return
 *              type, resulting a very big  return value.  This behaviour is at
 *              least questionable.  But  we can no longer change  that at this
 *              point.
 * @note        Not only  does this  function works under  the "C"  locale, but
 *              also assumes its execution character  set be what ruby calls an
 *              ASCII-compatible  character set;  which  does  not include  for
 *              instance EBCDIC or UTF-16LE.
 */
unsigned long ruby_strtoul(const char *str, char **endptr, int base);
RBIMPL_SYMBOL_EXPORT_END()

/*
 * We are making  the functions below to return `int`  instead of `bool`.  They
 * have been as such since their birth at 5f237d79033b2109afb768bc889611fa9630.
 */

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isascii(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     false  `c` is out of range of ASCII character set.
 * @retval     true   Yes it is.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isascii(int c)
{
    return '\0' <= c && c <= '\x7f';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isupper(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed  in IEEE 1003.1 section 7.3.1.1 "upper".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isupper(int c)
{
    return 'A' <= c && c <= 'Z';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `islower(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed  in IEEE 1003.1 section 7.3.1.1 "lower".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_islower(int c)
{
    return 'a' <= c && c <= 'z';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isalpha(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed in  either  IEEE  1003.1 section  7.3.1.1
 *                    "upper" or "lower".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isalpha(int c)
{
    return rb_isupper(c) || rb_islower(c);
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isdigit(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed  in IEEE 1003.1 section 7.3.1.1 "digit".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isdigit(int c)
{
    return '0' <= c && c <= '9';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isalnum(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed in  either  IEEE  1003.1 section  7.3.1.1
 *                    "upper", "lower", or "digit".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isalnum(int c)
{
    return rb_isalpha(c) || rb_isdigit(c);
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isxdigit(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed  in IEEE 1003.1 section 7.3.1.1 "xdigit".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isxdigit(int c)
{
    return rb_isdigit(c) || ('A' <= c && c <= 'F') || ('a' <= c && c <= 'f');
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isblank(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed  in IEEE 1003.1 section 7.3.1.1 "blank".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isblank(int c)
{
    return c == ' ' || c == '\t';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isspace(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed  in IEEE 1003.1 section 7.3.1.1 "space".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isspace(int c)
{
    return c == ' ' || ('\t' <= c && c <= '\r');
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `iscntrl(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed  in IEEE 1003.1 section 7.3.1.1 "cntrl".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_iscntrl(int c)
{
    return ('\0' <= c && c < ' ') || c == '\x7f';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Identical to rb_isgraph(), except it also returns true for `' '`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed in  either  IEEE  1003.1 section  7.3.1.1
 *                    "upper", "lower", "digit", "punct", or a `' '`.
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isprint(int c)
{
    return ' ' <= c && c <= '\x7e';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `ispunct(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed  in IEEE 1003.1 section 7.3.1.1 "punct".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_ispunct(int c)
{
    return !rb_isalnum(c);
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `isgraph(3)`.
 *
 * @param[in]  c      Byte in question to query.
 * @retval     true   `c`  is  listed in  either  IEEE  1003.1 section  7.3.1.1
 *                    "upper", "lower", "digit", or "punct".
 * @retval     false  Anything else.
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_isgraph(int c)
{
    return '!' <= c && c <= '\x7e';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `tolower(3)`.
 *
 * @param[in]  c          Byte in question to convert.
 * @retval     c          The  byte is  not listed  in in  IEEE 1003.1  section
 *                        7.3.1.1 "upper".
 * @retval     otherwise  Byte converted  using the map defined  in IEEE 1003.1
 *                        section 7.3.1 "tolower".
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_tolower(int c)
{
    return rb_isupper(c) ? (c|0x20) : c;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Our own locale-insensitive version of `toupper(3)`.
 *
 * @param[in]  c          Byte in question to convert.
 * @retval     c          The  byte is  not listed  in in  IEEE 1003.1  section
 *                        7.3.1.1 "lower".
 * @retval     otherwise  Byte converted  using the map defined  in IEEE 1003.1
 *                        section 7.3.1 "toupper".
 * @note       Not only  does this function  works under the POSIX  Locale, but
 *             also assumes its  execution character set be what  ruby calls an
 *             ASCII-compatible  character  set;  which does  not  include  for
 *             instance EBCDIC or UTF-16LE.
 * @warning    `c` is  an int.  This  means that when  you pass a  `char` value
 *             here, it  experiences "integer promotion" as  defined in ISO/IEC
 *             9899:2018 section 6.3.1.1 paragraph 1.
 */
static inline int
rb_toupper(int c)
{
    return rb_islower(c) ? (c&0x5f) : c;
}

/** @} */
#endif /* RBIMPL_CTYPE_H */
