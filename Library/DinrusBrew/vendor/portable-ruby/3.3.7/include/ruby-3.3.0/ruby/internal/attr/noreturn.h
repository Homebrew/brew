#ifndef RBIMPL_ATTR_NORETURN_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_NORETURN_H
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
 * @brief      Defines #RBIMPL_ATTR_NORETURN.
 */
#include "ruby/internal/has/attribute.h"
#include "ruby/internal/has/cpp_attribute.h"
#include "ruby/internal/has/declspec_attribute.h"

/** Wraps (or simulates) `[[noreturn]]` */
#if RBIMPL_HAS_DECLSPEC_ATTRIBUTE(noreturn)
# define RBIMPL_ATTR_NORETURN() __declspec(noreturn)

#elif RBIMPL_HAS_ATTRIBUTE(noreturn)
# define RBIMPL_ATTR_NORETURN() __attribute__((__noreturn__))

#elif RBIMPL_HAS_CPP_ATTRIBUTE(noreturn)
# define RBIMPL_ATTR_NORETURN() [[noreturn]]

#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112)
# define RBIMPL_ATTR_NORETURN() _Noreturn

#elif defined(_Noreturn)
# /* glibc <sys/cdefs.h> has this macro. */
# define RBIMPL_ATTR_NORETURN() _Noreturn

#else
# define RBIMPL_ATTR_NORETURN() /* void */
#endif

#endif /* RBIMPL_ATTR_NORETURN_H */
