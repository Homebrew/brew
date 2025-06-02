#ifndef RBIMPL_ATTR_NODISCARD_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_NODISCARD_H
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
 * @brief      Defines #RBIMPL_ATTR_NODISCARD.
 */
#include "ruby/internal/has/attribute.h"
#include "ruby/internal/has/c_attribute.h"
#include "ruby/internal/has/cpp_attribute.h"

/**
 * Wraps  (or simulates)  `[[nodiscard]]`.  In  C++  (at least  since C++20)  a
 * nodiscard attribute can  have a message why the result shall not be ignored.
 * However GCC attribute and SAL annotation cannot take them.
 */
#if RBIMPL_HAS_CPP_ATTRIBUTE(nodiscard)
# define RBIMPL_ATTR_NODISCARD() [[nodiscard]]
#elif RBIMPL_HAS_C_ATTRIBUTE(nodiscard)
# define RBIMPL_ATTR_NODISCARD() [[nodiscard]]
#elif RBIMPL_HAS_ATTRIBUTE(warn_unused_result)
# define RBIMPL_ATTR_NODISCARD() __attribute__((__warn_unused_result__))
#elif defined(_Check_return_)
# /* Take SAL definition. */
# define RBIMPL_ATTR_NODISCARD() _Check_return_
#else
# define RBIMPL_ATTR_NODISCARD() /* void */
#endif

#endif /* RBIMPL_ATTR_NODISCARD_H */
