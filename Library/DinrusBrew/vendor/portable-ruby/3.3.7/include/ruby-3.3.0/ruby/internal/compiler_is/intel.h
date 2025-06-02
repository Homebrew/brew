#ifndef RBIMPL_COMPILER_IS_INTEL_H                   /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_COMPILER_IS_INTEL_H
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
 * @brief      Defines RBIMPL_COMPILER_IS_Intel.
 */
#if ! defined(__INTEL_COMPILER)
# define RBIMPL_COMPILER_IS_Intel 0

#elif ! defined(__INTEL_COMPILER_UPDATE)
# define RBIMPL_COMPILER_IS_Intel 1
# /* __INTEL_COMPILER = XXYZ */
# define RBIMPL_COMPILER_VERSION_MAJOR (__INTEL_COMPILER / 100)
# define RBIMPL_COMPILER_VERSION_MINOR (__INTEL_COMPILER % 100 / 10)
# define RBIMPL_COMPILER_VERSION_PATCH (__INTEL_COMPILER       % 10)

#else
# define RBIMPL_COMPILER_IS_Intel 1
# /* __INTEL_COMPILER = XXYZ */
# define RBIMPL_COMPILER_VERSION_MAJOR (__INTEL_COMPILER / 100)
# define RBIMPL_COMPILER_VERSION_MINOR (__INTEL_COMPILER % 100 / 10)
# define RBIMPL_COMPILER_VERSION_PATCH __INTEL_COMPILER_UPDATE
#endif

#endif /* RBIMPL_COMPILER_IS_INTEL_H */
