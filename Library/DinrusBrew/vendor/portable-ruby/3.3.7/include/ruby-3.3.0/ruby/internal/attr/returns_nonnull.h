#ifndef RBIMPL_ATTR_RETURNS_NONNULL_H                /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_RETURNS_NONNULL_H
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
 * @brief      Defines #RBIMPL_ATTR_RETURNS_NONNULL.
 */
#include "ruby/internal/has/attribute.h"

/** Wraps (or simulates) `__attribute__((returns_nonnull))` */
#if defined(_Ret_nonnull_)
# /* Take SAL definition. */
# define RBIMPL_ATTR_RETURNS_NONNULL() _Ret_nonnull_

#elif RBIMPL_HAS_ATTRIBUTE(returns_nonnull)
# define RBIMPL_ATTR_RETURNS_NONNULL() __attribute__((__returns_nonnull__))

#else
# define RBIMPL_ATTR_RETURNS_NONNULL() /* void */
#endif

#endif /* RBIMPL_ATTR_RETURNS_NONNULL_H */
