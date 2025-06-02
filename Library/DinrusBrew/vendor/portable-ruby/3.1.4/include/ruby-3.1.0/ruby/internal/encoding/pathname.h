#ifndef RUBY_INTERNAL_ENCODING_PATHNAME_H            /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_PATHNAME_H
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
 * @brief      Routines to manipulate encodings of pathnames.
 */

#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/encoding/encoding.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_NONNULL(())
/**
 * Returns a path component directly adjacent to the passed pointer.
 *
 * ```
 * "/multi/byte/encoded/pathname.txt"
 *         ^    ^                   ^
 *         |    |                   +--- end
 *         |    +--- @return
 *         +--- path
 * ```
 *
 * @param[in]  path  Where to start scanning.
 * @param[in]  end   End of the path string.
 * @param[in]  enc   Encoding of the string.
 * @return     A pointer  in the  passed string where  the next  path component
 *             resides, or `end` if there is no next path component.
 */
char *rb_enc_path_next(const char *path, const char *end, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * Seeks for non-prefix  part of a pathname.   This can be a no-op  when the OS
 * has no  such concept  like a  path prefix.   But there  are OSes  where path
 * prefixes do exist.
 *
 * ```
 * "C:\multi\byte\encoded\pathname.txt"
 *  ^ ^                               ^
 *  | |                               +--- end
 *  | +--- @return
 *  +--- path
 * ```
 *
 * @param[in]  path  Where to start scanning.
 * @param[in]  end   End of the path string.
 * @param[in]  enc   Encoding of the string.
 * @return     A pointer in the passed  string where non-prefix part starts, or
 *             `path` if the OS does not have path prefix.
 */
char *rb_enc_path_skip_prefix(const char *path, const char *end, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * Returns the last path component.
 *
 * ```
 * "/multi/byte/encoded/pathname.txt"
 *        ^             ^           ^
 *        |             |           +--- end
 *        |             +--- @return
 *        +--- path
 * ```
 *
 * @param[in]  path  Where to start scanning.
 * @param[in]  end   End of the path string.
 * @param[in]  enc   Encoding of the string.
 * @return     A pointer  in the  passed string where  the last  path component
 *             resides, or `end` if there is no more path component.
 */
char *rb_enc_path_last_separator(const char *path, const char *end, rb_encoding *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * This just returns the passed end basically.  It makes difference in case the
 * passed string ends with tons of path separators like the following:
 *
 * ```
 * "/path/that/ends/with/lots/of/slashes//////////////"
 *  ^                                   ^             ^
 *  |                                   |             +--- end
 *  |                                   +--- @return
 *  +--- path
 * ```
 *
 * @param[in]  path  Where to start scanning.
 * @param[in]  end   End of the path string.
 * @param[in]  enc   Encoding of the string.
 * @return     A  pointer  in  the  passed   string  where  the  trailing  path
 *             separators  start,  or  `end`  if  there  is  no  trailing  path
 *             separators.
 *
 * @internal
 *
 * It  seems this  function  was  introduced to  mimic  what  POSIX says  about
 * `basename(3)`.
 */
char *rb_enc_path_end(const char *path, const char *end, rb_encoding *enc);

RBIMPL_ATTR_NONNULL((1, 4))
/**
 * Our own  encoding-aware version  of `basename(3)`.  Normally,  this function
 * returns the  last path  component of  the given name.   However in  case the
 * passed  name  ends  with a  path  separator,  it  returns  the name  of  the
 * directory, not  the last (empty)  component.  Also if  the passed name  is a
 * root directory, it  returns that root directory.  Note  however that Windows
 * filesystem have drive letters, which this function does not return.
 *
 * @param[in]      name     Target path.
 * @param[out]     baselen  Return buffer.
 * @param[in,out]  alllen   Number of bytes of `name`.
 * @param[enc]     enc      Encoding of `name`.
 * @return         The rightmost component of `name`.
 * @post           `baselen`, if passed,  is updated to be the  number of bytes
 *                 of the returned basename.
 * @post           `alllen`, if passed, is updated to be the number of bytes of
 *                 strings not considered as the basename.
 */
const char *ruby_enc_find_basename(const char *name, long *baselen, long *alllen, rb_encoding *enc);

RBIMPL_ATTR_NONNULL((1, 3))
/**
 * Our own  encoding-aware version of  `extname`.  This function  first applies
 * rb_enc_path_last_separator() to the passed name and only concerns its return
 * value (ignores  any parent directories).  This  function returns complicated
 * results:
 *
 * ```CXX
 * auto path = "...";
 * auto len = strlen(path);
 * auto ret = ruby_enc_find_extname(path, &len, rb_ascii8bit_encoding());
 *
 * switch(len) {
 * case 0:
 *     if (ret == 0) {
 *         // `path` is a file without extensions.
 *     }
 *     else {
 *         // `path` is a dotfile.
 *         // `ret` is the file's name.
 *     }
 *     break;
 *
 * case 1:
 *     // `path` _ends_ with a dot.
 *     // `ret` is that dot.
 *     break;
 *
 * default:
 *     // `path` has an extension.
 *     // `ret` is that extension.
 * }
 * ```
 *
 * @param[in]      name  Target path.
 * @param[in,out]  len   Number of bytes of `name`.
 * @param[in]      enc   Encoding of `name`.
 * @return         See above.
 * @post           `len`, if passed, is updated (see above).
 */
const char *ruby_enc_find_extname(const char *name, long *len, rb_encoding *enc);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_PATHNAME_H */
