#ifndef RBIMPL_GLOB_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_GLOB_H
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
 * @brief      Declares ::rb_glob().
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Type of a glob callback function.  Called every time glob scans a path.
 *
 * @param[in]  path       The path in question.
 * @param[in]  arg        The argument passed to rb_glob().
 * @param[in]  enc        Encoding of the path.
 * @retval     -1         Not enough memory to do the operation.
 * @retval     0          Operation successful.
 * @retval     otherwise  Opaque exception state.
 * @note       You can use rb_protect() to generate the return value.
 *
 * @internal
 *
 * This  is a  wrong design.   Type of  `enc` should  have been  `rb_encoding*`
 * instead of just `void*`.  But we cannot change the API any longer.
 *
 * Though not a part of our public API, the "opaque exception state" is in fact
 * an  enum ruby_tag_type.   You can  see the  potential "otherwise"  values by
 * looking at vm_core.h.
 */
typedef int ruby_glob_func(const char *path, VALUE arg, void *enc);

RBIMPL_ATTR_NONNULL(())
/**
 * The "glob"  operator.  Expands  the given pattern  against the  actual local
 * filesystem,  then  iterates  over  the expanded  filenames  by  calling  the
 * callback function.
 *
 * @param[in]  pattern        A glob pattern.
 * @param[in]  func           Identical to ruby_glob_func,  except it can raise
 *                            exceptions instead of returning opaque state.
 * @param[in]  arg            Extra argument passed to func.
 * @exception  rb_eException  Can propagate what `func` raises.
 * @note       The  language  accepted   as  the  pattern  is   not  a  regular
 *             expression.  It resembles shell's glob.
 */
void rb_glob(const char *pattern, void (*func)(const char *path, VALUE arg, void *enc), VALUE arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_glob(), except it returns opaque exception states instead of
 * raising exceptions.
 *
 * @param[in]  pattern  A glob pattern.
 * @param[in]  flags    No, you are not allowed to use this.  Just pass 0.
 * @param[in]  func     A callback function.
 * @param[in]  arg      Extra argument passed to func.
 * @return     Return value of `func`.
 *
 * @internal
 *
 * This function is  completely broken by design...  Not only  is there no sane
 * way to pass flags, but there also is no sane way to know what a return value
 * is meant to be.
 *
 * Though not a part of our public API, and @shyouhei thinks it's a failure not
 * to be  a public  API, the  flags can  be `FNM_EXTGLOB`,  `FNM_DOTMATCH` etc.
 * Look at dir.c for the list.
 *
 * Though  not a  part  of our  public  API, the  return value  is  in fact  an
 * enum ruby_tag_type.   You  can  see  the  potential  values  by  looking  at
 * vm_core.h.
 */
int ruby_glob(const char *pattern, int flags, ruby_glob_func *func, VALUE arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to  ruby_glob(), @shyouhei  currently suspects.   Historically you
 * had to  call this function  instead of  ruby_glob() if the  pattern included
 * "{x,y,...}" syntax.  However since commit 0f63d961169989a7f6dcf7c0487fe29da,
 * ruby_glob() also  supports that syntax.   It seems  as of writing  these two
 * functions  provide   basically  the   same  functionality  in   a  different
 * implementation.  Is this analysis right?  Correct me! :FIXME:
 *
 * @param[in]  pattern  A glob pattern.
 * @param[in]  flags    No, you are not allowed to use this.  Just pass 0.
 * @param[in]  func     A callback function.
 * @param[in]  arg      Extra argument passed to func.
 * @return     Return value of `func`.
 */
int ruby_brace_glob(const char *pattern, int flags, ruby_glob_func *func, VALUE arg);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_GLOB_H */
