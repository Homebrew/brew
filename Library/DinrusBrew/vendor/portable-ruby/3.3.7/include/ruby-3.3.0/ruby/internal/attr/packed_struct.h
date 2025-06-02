#ifndef RBIMPL_ATTR_PACKED_STRUCT_H                 /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_PACKED_STRUCT_H
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
 * @brief      Defines #RBIMPL_ATTR_PACKED_STRUCT_BEGIN,
 *             #RBIMPL_ATTR_PACKED_STRUCT_END,
 *             #RBIMPL_ATTR_PACKED_STRUCT_UNALIGNED_BEGIN, and
 *             #RBIMPL_ATTR_PACKED_STRUCT_UNALIGNED_END.
 */
#include "ruby/internal/config.h"

#ifndef RBIMPL_ATTR_PACKED_STRUCT_BEGIN
# define RBIMPL_ATTR_PACKED_STRUCT_BEGIN() /* void */
#endif
#ifndef RBIMPL_ATTR_PACKED_STRUCT_END
# define RBIMPL_ATTR_PACKED_STRUCT_END() /* void */
#endif

#if UNALIGNED_WORD_ACCESS
# define RBIMPL_ATTR_PACKED_STRUCT_UNALIGNED_BEGIN() RBIMPL_ATTR_PACKED_STRUCT_BEGIN()
# define RBIMPL_ATTR_PACKED_STRUCT_UNALIGNED_END() RBIMPL_ATTR_PACKED_STRUCT_END()
#else
# define RBIMPL_ATTR_PACKED_STRUCT_UNALIGNED_BEGIN() /* void */
# define RBIMPL_ATTR_PACKED_STRUCT_UNALIGNED_END() /* void */
#endif

#endif
