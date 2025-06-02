#ifndef RBIMPL_COMPILER_IS_SUNPRO_H                  /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_COMPILER_IS_SUNPRO_H
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
 * @brief      Defines RBIMPL_COMPILER_IS_SunPro.
 */
#if ! (defined(__SUNPRO_C) || defined(__SUNPRO_CC))
# define RBIMPL_COMPILER_IS_SunPro 0

#elif defined(__SUNPRO_C) && __SUNPRO_C >= 0x5100
# define RBIMPL_COMPILER_IS_SunPro 1
# /* __SUNPRO_C = 0xXYYZ */
# define RBIMPL_COMPILER_VERSION_MAJOR  (__SUNPRO_C >> 12)
# define RBIMPL_COMPILER_VERSION_MINOR ((__SUNPRO_C >> 8 & 0xF) * 10 + (__SUNPRO_C >> 4 & 0xF))
# define RBIMPL_COMPILER_VERSION_PATCH  (__SUNPRO_C      & 0xF)

#elif defined(__SUNPRO_CC) && __SUNPRO_CC >= 0x5100
# define RBIMPL_COMPILER_IS_SunPro 1
# /* __SUNPRO_CC = 0xXYYZ */
# define RBIMPL_COMPILER_VERSION_MAJOR  (__SUNPRO_CC >> 12)
# define RBIMPL_COMPILER_VERSION_MINOR ((__SUNPRO_CC >> 8 & 0xF) * 10 + (__SUNPRO_CC >> 4 & 0xF))
# define RBIMPL_COMPILER_VERSION_PATCH  (__SUNPRO_CC      & 0xF)

#elif defined(__SUNPRO_C)
# define RBIMPL_COMPILER_IS_SunPro 1
# /* __SUNPRO_C = 0xXYZ */
# define RBIMPL_COMPILER_VERSION_MAJOR (__SUNPRO_C >> 8)
# define RBIMPL_COMPILER_VERSION_MINOR (__SUNPRO_C >> 4 & 0xF)
# define RBIMPL_COMPILER_VERSION_PATCH (__SUNPRO_C      & 0xF)

#else
# define RBIMPL_COMPILER_IS_SunPro 1
# /* __SUNPRO_CC = 0xXYZ */
# define RBIMPL_COMPILER_VERSION_MAJOR (__SUNPRO_CC >> 8)
# define RBIMPL_COMPILER_VERSION_MINOR (__SUNPRO_CC >> 4 & 0xF)
# define RBIMPL_COMPILER_VERSION_PATCH (__SUNPRO_CC      & 0xF)
#endif

#endif /* RBIMPL_COMPILER_IS_SUNPRO_H */
