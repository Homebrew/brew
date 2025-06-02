#ifndef RBIMPL_DLLEXPORT_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_DLLEXPORT_H
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
 * @brief      Tweaking visibility of C variables/functions.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/compiler_is.h"

/**
 * Declaration of externally visible global variables.  Here "externally" means
 * they should  be visible  from extension  libraries.  Depending  on operating
 * systems (dynamic linkers,  to be precise), global variables inside  of a DLL
 * may  or may  not be  visible  form outside  of  that DLL  by default.   This
 * declaration manually tweaks  that default and ensures  the declared variable
 * be truly globally visible.
 *
 * ```CXX
 * extern VALUE foo;      // hidden on some OS
 * RUBY_EXTERN VALUE foo; // ensure visible
 * ```
 */
#undef RUBY_EXTERN
#if defined(RUBY_EXPORT)
# define RUBY_EXTERN extern
#elif defined(_WIN32)
# define RUBY_EXTERN extern __declspec(dllimport)
#else
# define RUBY_EXTERN extern
#endif

#ifndef RUBY_SYMBOL_EXPORT_BEGIN
# define RUBY_SYMBOL_EXPORT_BEGIN /* begin */
#endif

#ifndef RUBY_SYMBOL_EXPORT_END
# define RUBY_SYMBOL_EXPORT_END   /* end */
#endif

#ifndef RUBY_FUNC_EXPORTED
# define RUBY_FUNC_EXPORTED /* void */
#endif

/** @endcond */

/** Shortcut macro equivalent to `RUBY_SYMBOL_EXPORT_BEGIN extern "C" {`.
 * \@shyouhei finds it handy. */
#if defined(__DOXYGEN__)
# define RBIMPL_SYMBOL_EXPORT_BEGIN() /* void */
#elif defined(__cplusplus)
# define RBIMPL_SYMBOL_EXPORT_BEGIN() RUBY_SYMBOL_EXPORT_BEGIN extern "C" {
#else
# define RBIMPL_SYMBOL_EXPORT_BEGIN() RUBY_SYMBOL_EXPORT_BEGIN
#endif

/** Counterpart of #RBIMPL_SYMBOL_EXPORT_BEGIN */
#if defined(__DOXYGEN__)
# define RBIMPL_SYMBOL_EXPORT_END() /* void */
#elif defined(__cplusplus)
# define RBIMPL_SYMBOL_EXPORT_END() } RUBY_SYMBOL_EXPORT_END
#else
# define RBIMPL_SYMBOL_EXPORT_END()   RUBY_SYMBOL_EXPORT_END
#endif
#endif /* RBIMPL_DLLEXPORT_H */
