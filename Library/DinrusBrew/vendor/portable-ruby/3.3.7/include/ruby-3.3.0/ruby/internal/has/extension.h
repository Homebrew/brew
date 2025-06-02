#ifndef RBIMPL_HAS_EXTENSION_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_HAS_EXTENSION_H
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
 * @brief      Defines #RBIMPL_HAS_EXTENSION.
 */
#include "ruby/internal/has/feature.h"

/** Wraps (or simulates) `__has_extension`. */
#if defined(__has_extension)
# define RBIMPL_HAS_EXTENSION(_) __has_extension(_)
#else
# /* Pre-3.0 clang had __has_feature but not __has_extension. */
# define RBIMPL_HAS_EXTENSION(_) RBIMPL_HAS_FEATURE(_)
#endif

#endif /* RBIMPL_HAS_EXTENSION_H */
