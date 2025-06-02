#ifndef RBIMPL_ATTR_NOEXCEPT_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_NOEXCEPT_H
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
 * @brief      Defines #RBIMPL_ATTR_NOEXCEPT.
 *
 * This isn't actually an attribute in C++ but who cares...
 *
 * Mainly due  to aesthetic reasons,  this one is  rarely used in  the project.
 * But can  be handy on  occasions, especially when a  function's noexcept-ness
 * depends on its calling functions.
 *
 * ### Q&A ###
 *
 * - Q: Can a function that raises Ruby exceptions be attributed `noexcept`?
 *
 * - A: Yes.   `noexcept` is  about  C++ exceptions,  not  Ruby's.  They  don't
 *      interface each other.  You can  safely attribute a function that raises
 *      Ruby exceptions as `noexcept`.
 *
 * - Q: How, then, can I assert that  a function I wrote doesn't raise any Ruby
 *      exceptions?
 *
 * - A: `__attribute__((__leaf__))` is for that purpose.  A function attributed
 *      as leaf can still throw C++  exceptions, but not Ruby's.  Note however,
 *      that it's extremely difficult -- if  not impossible -- to assert that a
 *      function  doesn't  raise any  Ruby  exceptions  at  all.  Use  of  that
 *      attribute is not  recommended; mere mortals can't properly  use that by
 *      hand.
 *
 * - Q: Does it make sense to attribute an inline function `noexcept`?
 *
 * - A: I thought so before.  But no, I don't think they are useful any longer.
 *
 *     - When an  inline function attributed `noexcept`  actually doesn't throw
 *       any  exceptions at  all:  these days  I don't  see  any difference  in
 *       generated assembly  by adding/removing this attribute.   C++ compilers
 *       get smarter and  smarter.  Today they can infer if  it actually throws
 *       or not without any annotations by humans (correct me if I'm wrong).
 *
 *     - When an inline function attributed `noexcepr` actually _does_ throw an
 *       exception:  they  have to  call  `std::terminate`  then (C++  standard
 *       mandates  so).  This  means exception  handling routines  are actually
 *       enforced, not  omitted.  This doesn't impact  runtime performance (The
 *       Itanium C++ ABI has zero-cost  exception handling), but does impact on
 *       generated binary size.  This is bad.
 */
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/has/feature.h"

/** Wraps (or simulates) C++11 `noexcept` */
#if ! defined(__cplusplus)
# /* Doesn't make sense. */
# define RBIMPL_ATTR_NOEXCEPT(_) /* void */

#elif RBIMPL_HAS_FEATURE(cxx_noexcept)
# define RBIMPL_ATTR_NOEXCEPT(_) noexcept(noexcept(_))

#elif defined(__GXX_EXPERIMENTAL_CXX0X__) && __GXX_EXPERIMENTAL_CXX0X__
# define RBIMPL_ATTR_NOEXCEPT(_) noexcept(noexcept(_))

#elif defined(__INTEL_CXX11_MODE__)
# define RBIMPL_ATTR_NOEXCEPT(_) noexcept(noexcept(_))

#elif RBIMPL_COMPILER_SINCE(MSVC, 19, 0, 0)
# define RBIMPL_ATTR_NOEXCEPT(_) noexcept(noexcept(_))

#elif __cplusplus >= 201103L
# define RBIMPL_ATTR_NOEXCEPT(_) noexcept(noexcept(_))

#else
# define RBIMPL_ATTR_NOEXCEPT(_) /* void */
#endif

#endif /* RBIMPL_ATTR_NOEXCEPT_H */
