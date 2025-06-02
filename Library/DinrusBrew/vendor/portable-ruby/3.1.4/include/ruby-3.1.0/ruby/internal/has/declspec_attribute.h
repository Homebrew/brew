#ifndef RBIMPL_HAS_DECLSPEC_ATTRIBUTE_H              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_H
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
 * @brief      Defines #RBIMPL_HAS_DECLSPEC_ATTRIBUTE.
 */
#include "ruby/internal/compiler_since.h"

/** Wraps (or simulates) `__has_declspec_attribute`. */
#if defined(__has_declspec_attribute)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE(_) __has_declspec_attribute(_)
#else
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE(_) (RBIMPL_HAS_DECLSPEC_ATTRIBUTE_ ## _)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_align       RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_deprecated  RBIMPL_COMPILER_SINCE(MSVC,13, 0, 0)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_dllexport   RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_dllimport   RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_empty_bases RBIMPL_COMPILER_SINCE(MSVC,19, 0, 23918)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_noalias     RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_noinline    RBIMPL_COMPILER_SINCE(MSVC,13, 0, 0)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_noreturn    RBIMPL_COMPILER_SINCE(MSVC,11, 0, 0)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_nothrow     RBIMPL_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RBIMPL_HAS_DECLSPEC_ATTRIBUTE_restrict    RBIMPL_COMPILER_SINCE(MSVC,14, 0, 0)
# /* Note that "8, 0, 0" might be inaccurate. */
# if ! defined(__cplusplus)
#  /* Clang has this in both C/C++, but MSVC has this in C++ only.*/
#  undef RBIMPL_HAS_DECLSPEC_ATTRIBUTE_nothrow
# endif
#endif

#endif /* RBIMPL_HAS_DECLSPEC_ATTRIBUTE_H */
