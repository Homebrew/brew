#ifndef RBIMPL_COMPILER_IS_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_COMPILER_IS_H
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
 * @brief      Defines #RBIMPL_COMPILER_IS.
 */

/**
 * @brief   Checks if the compiler is of given brand.
 * @param   cc     Compiler brand, like `MSVC`.
 * @retval  true   It is.
 * @retval  false  It isn't.
 */
#define RBIMPL_COMPILER_IS(cc) RBIMPL_COMPILER_IS_ ## cc

#include "ruby/internal/compiler_is/apple.h"
#include "ruby/internal/compiler_is/clang.h"
#include "ruby/internal/compiler_is/gcc.h"
#include "ruby/internal/compiler_is/intel.h"
#include "ruby/internal/compiler_is/msvc.h"
#include "ruby/internal/compiler_is/sunpro.h"
/* :TODO: Other possible compilers to support:
 *
 * - IBM  XL: recent  XL are  clang-backended  so some  tweaks like  we do  for
 *   Apple's might be needed.
 *
 * - ARM's armclang: ditto, it can be clang-backended.  */

#endif /* RBIMPL_COMPILER_IS_H */
