#ifndef RBIMPL_INTERN_FILE_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_FILE_H
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
 * @brief      Public APIs related to ::rb_cFile.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* file.c */

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_file_expand_path(), except how arguments are passed.
 *
 * @param[in]  argc                Number of objects of `argv`.
 * @param[in]  argv                Filename, and base directory, in that order.
 * @exception  rb_eArgError        Wrong `argc`.
 * @exception  rb_eTypeError       Non-string passed.
 * @exception  rb_eEncCompatError  No conversion from arguments to a path.
 * @return     Expanded path.
 *
 * @internal
 *
 * It seems nobody actually uses this function right now.  Maybe delete it?
 */
VALUE rb_file_s_expand_path(int argc, const VALUE *argv);

/**
 * Identical  to rb_file_absolute_path(),  except  it additionally  understands
 * `~`.  If a given pathname starts  with `~someone/`, that part expands to the
 * user's home directory (or that of current process' owner's in case of `~/`).
 *
 * @param[in]  fname               Relative file name.
 * @param[in]  dname               Lookup  base  directory  name,  or  in  case
 *                                 ::RUBY_Qnil is  passed the  process' current
 *                                 working directory is assumed.
 * @exception  rb_eArgError        Home directory is not absolute.
 * @exception  rb_eTypeError       Non-string passed.
 * @exception  rb_eEncCompatError  No conversion from arguments to a path.
 * @return     Expanded path.
 */
VALUE rb_file_expand_path(VALUE fname, VALUE dname);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_file_absolute_path(), except how arguments are passed.
 *
 * @param[in]  argc                Number of objects of `argv`.
 * @param[in]  argv                Filename, and base directory, in that order.
 * @exception  rb_eArgError        Wrong `argc`.
 * @exception  rb_eTypeError       Non-string passed.
 * @exception  rb_eEncCompatError  No conversion from arguments to a path.
 * @return     Expanded path.
 *
 * @internal
 *
 * It seems nobody actually uses this function right now.  Maybe delete it?
 */
VALUE rb_file_s_absolute_path(int argc, const VALUE *argv);

/**
 * Maps a  relative path  to its absolute  representation.  Relative  paths are
 * referenced  from the  passed directory  name, or  from the  process' current
 * working directory in case ::RUBY_Qnil is passed.
 *
 * @param[in]  fname               Relative file name.
 * @param[in]  dname               Lookup  base  directory  name,  or  in  case
 *                                 ::RUBY_Qnil is  passed the  process' current
 *                                 working directory is assumed.
 * @exception  rb_eArgError        Strings contain NUL bytes.
 * @exception  rb_eTypeError       Non-string passed.
 * @exception  rb_eEncCompatError  No conversion from arguments to a path.
 * @return     Expanded path.
 */
VALUE rb_file_absolute_path(VALUE fname, VALUE dname);

/**
 * Strips a file path's last component  (and trailing separators if any).  This
 * function is relatively  simple on POSIX environments; just  splits the input
 * with  `/`, strips  the  last one,  if something  remains  joins them  again,
 * otherwise the return value is `"."`.   However when it comes to Windows this
 * function is  quite very  much complicated.   We have to  take UNC  etc. into
 * account.  So for instance `"C:foo"`'s dirname is `"C:."`.
 *
 * @param[in]  fname               File name to strip.
 * @exception  rb_eTypeError       `fname` is not a String.
 * @exception  rb_eArgError        `fname` contains NUL bytes.
 * @exception  rb_eEncCompatError  `fname`'s encoding is not path-compat.
 * @return     A dirname of `fname`.
 * @note       This is a "pure" operation;  it computes the return value solely
 *             from the passed object and never does any file IO.
 */
VALUE rb_file_dirname(VALUE fname);

RBIMPL_ATTR_NONNULL(())
/**
 * Resolves a  feature's path.  This  function takes for instance  `"json"` and
 * `[".so", ".rb"]`,  and iterates  over the  `$LOAD_PATH` to  see if  there is
 * either `json.so` or `json.rb` in the directory.
 *
 * This is not what everything `require`  does, but at least `require` is built
 * on top of it.
 *
 * @param[in,out]  feature             File to search, and return buffer.
 * @param[in]      exts                List of file extensions.
 * @exception      rb_eTypeError       `feature` is not a String.
 * @exception      rb_eArgError        `feature` contains NUL bytes.
 * @exception      rb_eEncCompatError  `feature`'s encoding is not path-compat.
 * @retval         0                   Not found
 * @retval         otherwise           Found index in `ext`, plus one.
 * @post           `*feature` is a resolved path.
 */
int rb_find_file_ext(VALUE *feature, const char *const *exts);

/**
 * Identical  to rb_find_file_ext(),  except it  takes  a feature  name and  is
 * extension  at once,  e.g. `"json.rb"`.   This  difference is  much like  how
 * `require` and `load` are different.
 *
 * @param[in]  path                A path relative to `$LOAD_PATH`.
 * @exception  rb_eTypeError       `path` is not a String.
 * @exception  rb_eArgError        `path` contains NUL bytes.
 * @exception  rb_eEncCompatError  `path`'s encoding is not path-compat.
 * @return     Expanded path.
 */
VALUE rb_find_file(VALUE path);

/**
 * Queries  if  the  given path  is  either  a  directory,  or a  symlink  that
 * (potentially recursively) points to such thing.
 *
 * @param[in]  _                   Ignored (why...?)
 * @param[in]  path                String,  or IO.   In  case of  IO it  issues
 *                                 `fstat(2)` instead of `stat(2)`.
 * @exception  rb_eFrozenError     `path` is a frozen IO (why...?)
 * @exception  rb_eTypeError       `path` is neither String nor IO.
 * @exception  rb_eArgError        `path` contains NUL bytes.
 * @exception  rb_eEncCompatError  `path`'s encoding is not path-compat.
 * @retval     RUBY_Qtrue          `path` is a directory.
 * @retval     RUBY_Qfalse         Otherwise.
 */
VALUE rb_file_directory_p(VALUE _, VALUE path);

/**
 * Converts a  string into an  "OS Path" encoding,  if any.  In  most operating
 * systems there are  no such things like per-OS default  encoding of filename.
 * For them this  function is no-op.  However most notably  on MacOS, pathnames
 * are UTF-8 encoded.  It converts the given string into such encoding.
 *
 * @param[in]  path                An instance of ::rb_cString.
 * @exception  rb_eEncCompatError  `path`'s encoding is not path-compat.
 * @return     `path`'s contents converted to the OS' path encoding.
 */
VALUE rb_str_encode_ospath(VALUE path);

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_PURE()
/**
 * Queries if the given path is an  absolute path.  On POSIX environments it is
 * as easy  as `path[0]  == '/'`.   However on Windows,  drive letters  and UNC
 * paths are also taken into account.
 *
 * @param[in]  path  A possibly relative path string.
 * @retval     1     `path` is absolute.
 * @retval     0     `path` is relative.
 */
int rb_is_absolute_path(const char *path);

/**
 * Queries  the file  size  of the  given file.   Because  this function  calls
 * `fstat(2)`  internally, it  is  a failure  to  pass a  closed  file to  this
 * function.
 *
 * This function flushes the passed file's buffer if any.  Can take time.
 *
 * @param[in]   file                 A file object.
 * @exception   rb_eFrozenError      `file` is frozen.
 * @exception   rb_eIOError          `file` is closed.
 * @exception   rb_eSystemCallError  Permission denied etc.
 * @exception   rb_eNoMethodError    The given non-file object doesn't respond
 *                                   to `#size`.
 * @return      The size of the passed file.
 * @note        Passing a non-regular file such as a UNIX domain socket to this
 *              function  is   not  a  failure.    But  the  return   value  is
 *              unpredictable.  POSIX's `<sys/stat.h>` states  that "the use of
 *              this field is unspecified" then.
 */
off_t rb_file_size(VALUE file);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_FILE_H */
