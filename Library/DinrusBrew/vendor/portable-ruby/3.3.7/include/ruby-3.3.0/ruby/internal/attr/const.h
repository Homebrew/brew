#ifndef RBIMPL_ATTR_CONST_H                          /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_CONST_H
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
 * @brief      Defines #RBIMPL_ATTR_CONST.
 */
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/has/attribute.h"
#include "ruby/internal/has/declspec_attribute.h"

/** Wraps (or simulates) `__attribute__((const))` */
#if RBIMPL_HAS_ATTRIBUTE(const)
# define RBIMPL_ATTR_CONST() __attribute__((__const__))
#elif RBIMPL_HAS_DECLSPEC_ATTRIBUTE(noalias)
# /* If a function can be a const, that is also a noalias. */
# define RBIMPL_ATTR_CONST() __declspec(noalias)
#elif RBIMPL_COMPILER_SINCE(SunPro, 5, 10, 0)
# define RBIMPL_ATTR_CONST() _Pragma("no_side_effect")
#else
# define RBIMPL_ATTR_CONST() /* void */
#endif

/** Enables #RBIMPL_ATTR_CONST if and only if. ! #RUBY_DEBUG. */
#if !defined(RUBY_DEBUG) || !RUBY_DEBUG
# define RBIMPL_ATTR_CONST_UNLESS_DEBUG() RBIMPL_ATTR_CONST()
#else
# define RBIMPL_ATTR_CONST_UNLESS_DEBUG() /* void */
#endif

#endif /* RBIMPL_ATTR_CONST_H */
