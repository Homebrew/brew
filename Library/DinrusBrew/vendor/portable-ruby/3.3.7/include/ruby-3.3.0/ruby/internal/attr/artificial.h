#ifndef RBIMPL_ATTR_ARTIFICIAL_H                     /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_ARTIFICIAL_H
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
 * @brief      Defines #RBIMPL_ATTR_ARTIFICIAL.
 *
 * ### Q&A ###
 *
 * - Q: What is this attribute?  I don't get what GCC manual is talking about.
 *
 * - A: In  short  it  is  an  attribute to  manipulate  GDB  backtraces.   The
 *      attribute    makes    the   best    sense    when    it   comes    with
 *      __attribute__((always_inline)).   When a  function annotated  with this
 *      attribute gets inlined, and when you  somehow look at a backtrace which
 *      includes such  inlined call site,  then the backtrace shows  the caller
 *      and  not the  callee.  This  is handy  for instance  when an  identical
 *      function is inlined  more than once in a single  big function.  On such
 *      case it gets  vital to know where the inlining  happened in the callee.
 *      See also https://stackoverflow.com/a/21936099
 */
#include "ruby/internal/has/attribute.h"

/** Wraps (or simulates) `__attribute__((artificial))` */
#if RBIMPL_HAS_ATTRIBUTE(artificial)
# define RBIMPL_ATTR_ARTIFICIAL() __attribute__((__artificial__))
#else
# define RBIMPL_ATTR_ARTIFICIAL() /* void */
#endif

#endif /* RBIMPL_ATTR_ARTIFICIAL_H */
