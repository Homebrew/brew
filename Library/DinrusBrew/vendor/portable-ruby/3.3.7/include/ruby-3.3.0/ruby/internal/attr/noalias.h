#ifndef RBIMPL_ATTR_NOALIAS_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_NOALIAS_H
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
 * @brief      Defines #RBIMPL_ATTR_NOALIAS.
 *
 * ### Q&A ###
 *
 * - Q: There  are  seemingly   similar  attributes  named  #RBIMPL_ATTR_CONST,
 *      #RBIMPL_ATTR_PURE, and #RBIMPL_ATTR_NOALIAS.  What are the difference?
 *
 * - A: Allowed operations are different.
 *
 *     - #RBIMPL_ATTR_CONST ... Functions attributed by this are not allowed to
 *       read/write  _any_ pointers  at all  (there are  exceptional situations
 *       when  reading a  pointer is  possible but  forget that;  they are  too
 *       exceptional  to be  useful).  Just  remember that  everything pointer-
 *       related are NG.
 *
 *     - #RBIMPL_ATTR_PURE  ...   Functions attributed  by  this  can read  any
 *       nonvolatile pointers, but  no writes are allowed at  all.  The ability
 *       to read _any_ nonvolatile pointers  makes it possible to mark ::VALUE-
 *       taking functions as being pure, as long as they are read-only.
 *
 *     - #RBIMPL_ATTR_NOALIAS  ...  Can  both   read/write,  but  only  through
 *       pointers  passed to  the function  as parameters.   This is  a typical
 *       situation when you create a  C++ non-static member function which only
 *       concerns `this`.  No  global variables are allowed  to read/write.  So
 *       this is not a super-set of being pure.  If you want to read something,
 *       that has to  be passed to the function as  a pointer.  ::VALUE -taking
 *       functions thus cannot be attributed as such.
 */
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/has/declspec_attribute.h"

/** Wraps (or simulates) `__declspec((noalias))` */
#if RBIMPL_COMPILER_BEFORE(Clang, 12, 0, 0)
# /*
#  * `::llvm::Attribute::ArgMemOnly`  was buggy  before.  Maybe  because nobody
#  * actually seriously used it.  It seems they somehow mitigated the situation
#  * in  LLVM  12.  Still  not  found  the  exact  changeset which  fiexed  the
#  * attribute, though.
#  *
#  * :FIXME: others (armclang, xlclang, ...) can also be affected?
#  */
# define RBIMPL_ATTR_NOALIAS() /* void */
#elif RBIMPL_HAS_DECLSPEC_ATTRIBUTE(noalias)
# define RBIMPL_ATTR_NOALIAS() __declspec(noalias)
#else
# define RBIMPL_ATTR_NOALIAS() /* void */
#endif

#endif /* RBIMPL_ATTR_NOALIAS_H */
