#ifndef RBIMPL_COMPILER_IS_APPLE_H                   /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_COMPILER_IS_APPLE_H
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
 * @brief      Defines RBIMPL_COMPILER_IS_Apple.
 *
 * Apple  ships clang.   Problem is,  its  `__clang_major__` etc.  are not  the
 * upstream LLVM  version, but XCode's.  We  have to think Apple's  is distinct
 * from LLVM's,  when it comes  to compiler  detection business in  this header
 * file.
 */
#if ! defined(__clang__)
# define RBIMPL_COMPILER_IS_Apple 0

#elif ! defined(__apple_build_version__)
# define RBIMPL_COMPILER_IS_Apple 0

#else
# define RBIMPL_COMPILER_IS_Apple 1
# define RBIMPL_COMPILER_VERSION_MAJOR __clang_major__
# define RBIMPL_COMPILER_VERSION_MINOR __clang_minor__
# define RBIMPL_COMPILER_VERSION_PATCH __clang_patchlevel__
#endif

#endif /* RBIMPL_COMPILER_IS_APPLE_H */
