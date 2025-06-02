#ifndef RUBY_BACKWARD2_STDARG_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_BACKWARD2_STDARG_H
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
 * @brief      Defines old #_
 *
 * Nobody should  ever use these  macros any  longer.  No known  compilers lack
 * prototypes today.  It's 21st century.  Just forget them.
 */

#undef _
/**
 * @deprecated  Nobody practically needs this macro any longer.
 * @brief       This was a transition path from K&R to ANSI.
 */
#ifdef HAVE_PROTOTYPES
# define _(args) args
#else
# define _(args) ()
#endif

#undef __
/**
 * @deprecated  Nobody practically needs this macro any longer.
 * @brief       This was a transition path from K&R to ANSI.
 */
#ifdef HAVE_STDARG_PROTOTYPES
# define __(args) args
#else
# define __(args) ()
#endif

/**
 * Functions  declared using  this  macro take  arbitrary arguments,  including
 * void.
 *
 * ```CXX
 * void func(ANYARGS);
 * ```
 *
 * This  was a  necessary  evil when  there  was no  such  thing like  function
 * overloading.  But it  is the 21st century today.  People  generally need not
 * use this.  Just use a granular typed function.
 *
 * @see ruby::backward::cxxanyargs
 */
#ifdef __cplusplus
#define ANYARGS ...
#else
#define ANYARGS
#endif

#endif /* RUBY_BACKWARD2_STDARG_H */
