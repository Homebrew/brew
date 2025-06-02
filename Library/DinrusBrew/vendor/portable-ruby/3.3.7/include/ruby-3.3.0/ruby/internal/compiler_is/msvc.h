#ifndef RBIMPL_COMPILER_IS_MSVC_H                    /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_COMPILER_IS_MSVC_H
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
 * @brief      Defines RBIMPL_COMPILER_IS_MSVC.
 */
#include "ruby/internal/compiler_is/clang.h"
#include "ruby/internal/compiler_is/intel.h"

#if ! defined(_MSC_VER)
# define RBIMPL_COMPILER_IS_MSVC 0

#elif RBIMPL_COMPILER_IS(Clang)
# define RBIMPL_COMPILER_IS_MSVC 0

#elif RBIMPL_COMPILER_IS(Intel)
# define RBIMPL_COMPILER_IS_MSVC 0

#elif _MSC_VER >= 1400
# define RBIMPL_COMPILER_IS_MSVC 1
# /* _MSC_FULL_VER = XXYYZZZZZ */
# define RBIMPL_COMPILER_VERSION_MAJOR (_MSC_FULL_VER / 10000000)
# define RBIMPL_COMPILER_VERSION_MINOR (_MSC_FULL_VER % 10000000 / 100000)
# define RBIMPL_COMPILER_VERSION_PATCH (_MSC_FULL_VER            % 100000)

#elif defined(_MSC_FULL_VER)
# define RBIMPL_COMPILER_IS_MSVC 1
# /* _MSC_FULL_VER = XXYYZZZZ */
# define RBIMPL_COMPILER_VERSION_MAJOR (_MSC_FULL_VER / 1000000)
# define RBIMPL_COMPILER_VERSION_MINOR (_MSC_FULL_VER % 1000000 / 10000)
# define RBIMPL_COMPILER_VERSION_PATCH (_MSC_FULL_VER           % 10000)

#else
# define RBIMPL_COMPILER_IS_MSVC 1
# /* _MSC_VER = XXYY */
# define RBIMPL_COMPILER_VERSION_MAJOR (_MSC_VER / 100)
# define RBIMPL_COMPILER_VERSION_MINOR (_MSC_VER % 100)
# define RBIMPL_COMPILER_VERSION_PATCH 0
#endif

#endif /* RBIMPL_COMPILER_IS_MSVC_H */
