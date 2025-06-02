#ifndef RBIMPL_ATTR_DIAGNOSE_IF_H                    /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_DIAGNOSE_IF_H
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
 * @brief      Defines #RBIMPL_ATTR_DIAGNOSE_IF.
 */
#include "ruby/internal/has/attribute.h"
#include "ruby/internal/warning_push.h"

/** Wraps (or simulates) `__attribute__((diagnose_if))` */
#if RBIMPL_COMPILER_BEFORE(Clang, 5, 0, 0)
# /* https://bugs.llvm.org/show_bug.cgi?id=34319 */
# define RBIMPL_ATTR_DIAGNOSE_IF(_, __, ___) /* void */

#elif RBIMPL_HAS_ATTRIBUTE(diagnose_if)
# define RBIMPL_ATTR_DIAGNOSE_IF(_, __, ___) \
    RBIMPL_WARNING_PUSH() \
    RBIMPL_WARNING_IGNORED(-Wgcc-compat) \
    __attribute__((__diagnose_if__(_, __, ___))) \
    RBIMPL_WARNING_POP()

#else
# define RBIMPL_ATTR_DIAGNOSE_IF(_, __, ___) /* void */
#endif

#endif /* RBIMPL_ATTR_DIAGNOSE_IF_H */
