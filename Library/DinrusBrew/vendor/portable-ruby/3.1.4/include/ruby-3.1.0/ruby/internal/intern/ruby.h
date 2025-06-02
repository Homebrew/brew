#ifndef RBIMPL_INTERN_RUBY_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_RUBY_H
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
 * @brief      Process-global APIs.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* ruby.c */
/** @alias{rb_get_argv} */
#define rb_argv rb_get_argv()

/**
 * The value of `$0` at process bootup.
 *
 * @note  This is just a snapshot of `$0`, not the backend storage of it.  `$0`
 *        could  become something  different because  it is  a writable  global
 *        variable.  Modifying  it for instance affects  `ps(1)` output.  Don't
 *        assume they are synced.
 */
RUBY_EXTERN VALUE rb_argv0;

/* io.c */

/**
 * Queries the arguments passed to the current process that you can access from
 * Ruby as `ARGV`.
 *
 * @return  An array of strings containing arguments passed to the process.
 */
VALUE rb_get_argv(void);

/* ruby.c */

RBIMPL_ATTR_NONNULL(())
/**
 * Loads the given  file.  This function opens the given  pathname for reading,
 * parses the contents as a Ruby  script, and returns an opaque "node" pointer.
 * You can then pass it to ruby_run_node() for evaluation.
 *
 * @param[in]  file  File name, or "-" to read from stdin.
 * @return     Opaque "node" pointer.
 */
void *rb_load_file(const char *file);

/**
 * Identical to rb_load_file(), except it takes the argument as a Ruby's string
 * instead of C's.
 *
 * @param[in]  file  File name, or "-" to read from stdin.
 * @return     Opaque "node" pointer.
 */
void *rb_load_file_str(VALUE file);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_RUBY_H */
