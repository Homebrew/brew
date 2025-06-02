#ifndef RBIMPL_COMPILER_IS_GCC_H                     /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_COMPILER_IS_GCC_H
/**
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
 * @brief      Defines RBIMPL_COMPILER_IS_GCC.
 */
#include "ruby/internal/compiler_is/apple.h"
#include "ruby/internal/compiler_is/clang.h"
#include "ruby/internal/compiler_is/intel.h"

#if ! defined(__GNUC__)
# define RBIMPL_COMPILER_IS_GCC 0

#elif RBIMPL_COMPILER_IS(Apple)
# define RBIMPL_COMPILER_IS_GCC 0

#elif RBIMPL_COMPILER_IS(Clang)
# define RBIMPL_COMPILER_IS_GCC 0

#elif RBIMPL_COMPILER_IS(Intel)
# define RBIMPL_COMPILER_IS_GCC 0

#else
# define RBIMPL_COMPILER_IS_GCC 1
# define RBIMPL_COMPILER_VERSION_MAJOR __GNUC__
# define RBIMPL_COMPILER_VERSION_MINOR __GNUC_MINOR__
# define RBIMPL_COMPILER_VERSION_PATCH __GNUC_PATCHLEVEL__
#endif

#endif /* RBIMPL_COMPILER_IS_GCC_H */
