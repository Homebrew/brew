#ifndef RBIMPL_ANYARGS_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ANYARGS_H
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
 * @brief      Function overloads to issue warnings around #ANYARGS.
 *
 * For instance ::rb_define_method  takes a pointer to  #ANYARGS -ed functions,
 * which in  fact varies 18  different prototypes.   We still need  to preserve
 * #ANYARGS for storages but why not check the consistencies if possible.  With
 * those complex macro overlays defined in  this header file, use of a function
 * pointer gets checked against the corresponding arity argument.
 *
 * ### Q&A ###
 *
 * - Q: Where did the magic number "18" came from in the description above?
 *
 * - A: Count the case branch of `vm_method.c:call_cfunc_invoker_func()`.  Note
 *      also that the 18  branches has lasted for at least  25 years.  See also
 *      commit 200e0ee2fd3c1c006c528874a88f684447215524.
 *
 * - Q: What is this `__weakref__` thing?
 *
 * - A: That is a kind of function overloading mechanism that GCC provides.  In
 *      this   case  for   instance  `rb_define_method_00`   is  an   alias  of
 *      ::rb_define_method, with a strong type.
 *
 * - Q: What is this `__transparent_union__` thing?
 *
 *   A: That  is  another  kind  of function  overloading  mechanism  that  GCC
 *      provides.   In this  case  the attributed  function  pointer is  either
 *      `VALUE(*)(int,VALUE*,VALUE)` or `VALUE(*)(int,const VALUE*,VALUE)`.
 *
 *      This is better than `void*` or #ANYARGS because we can reject all other
 *      possibilities than the two.
 *
 * - Q: What does this #rb_define_method macro mean?
 *
 * - A: It  selects  appropriate  alias  of  the  ::rb_define_method  function,
 *      depending on the last (arity) argument.
 *
 * - Q: Why the special case for ::rb_f_notimplement ?
 *
 * - A: Function   pointer  to   ::rb_f_notimplement   is   special  cased   in
 *      `vm_method.c:rb_add_method_cfunc()`.   That should  be  handled by  the
 *      `__builtin_choose_expr`   chain  inside   of  #rb_define_method   macro
 *      expansion.      In    order     to    do     so,    comparison     like
 *      `(func == rb_f_notimplement)`        is        inappropriate        for
 *      `__builtin_choose_expr`'s  expression  (which  must be  a  compile-time
 *      integer constant  but the address  of ::rb_f_notimplement is  not fixed
 *      until      the      linker).        Instead      we      are      using
 *      `__builtin_types_compatible_p`, and in doing  so we need to distinguish
 *      ::rb_f_notimplement from others, by type.
 */
#include "ruby/internal/attr/maybe_unused.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/weakref.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/config.h"
#include "ruby/internal/has/attribute.h"
#include "ruby/internal/intern/class.h"
#include "ruby/internal/intern/vm.h"
#include "ruby/internal/method.h"
#include "ruby/internal/value.h"
#include "ruby/backward/2/stdarg.h"

#if defined(__cplusplus)
# include "ruby/backward/cxxanyargs.hpp"

#elif defined(_WIN32) || defined(__CYGWIN__)
# /* Skip due to [Bug #16134] */

#elif ! RBIMPL_HAS_ATTRIBUTE(transparent_union)
# /* :TODO: improve here, please find a way to support. */

#elif ! defined(HAVE_VA_ARGS_MACRO)
# /* :TODO: improve here, please find a way to support. */

#else
# /** @cond INTERNAL_MACRO */
# if ! defined(HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P)
#  define RBIMPL_CFUNC_IS_rb_f_notimplement(f) 0
# else
#  define RBIMPL_CFUNC_IS_rb_f_notimplement(f) \
    __builtin_types_compatible_p(             \
        __typeof__(f),                        \
        __typeof__(rb_f_notimplement))
# endif

# if ! defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
#  define RBIMPL_ANYARGS_DISPATCH(expr, truthy, falsy) (falsy)
# else
#  define RBIMPL_ANYARGS_DISPATCH(expr, truthy, falsy) \
    __builtin_choose_expr(                            \
        __builtin_choose_expr(                        \
            __builtin_constant_p(expr),               \
            (expr), 0),                               \
        (truthy), (falsy))
# endif

# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_singleton_method_m2, rb_define_singleton_method_m3)
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_singleton_method_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_m2(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_00(n) RBIMPL_ANYARGS_DISPATCH((n) ==  0, rb_define_singleton_method_00, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_m1(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_01(n) RBIMPL_ANYARGS_DISPATCH((n) ==  1, rb_define_singleton_method_01, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_00(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_02(n) RBIMPL_ANYARGS_DISPATCH((n) ==  2, rb_define_singleton_method_02, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_01(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_03(n) RBIMPL_ANYARGS_DISPATCH((n) ==  3, rb_define_singleton_method_03, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_02(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_04(n) RBIMPL_ANYARGS_DISPATCH((n) ==  4, rb_define_singleton_method_04, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_03(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_05(n) RBIMPL_ANYARGS_DISPATCH((n) ==  5, rb_define_singleton_method_05, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_04(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_06(n) RBIMPL_ANYARGS_DISPATCH((n) ==  6, rb_define_singleton_method_06, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_05(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_07(n) RBIMPL_ANYARGS_DISPATCH((n) ==  7, rb_define_singleton_method_07, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_06(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_08(n) RBIMPL_ANYARGS_DISPATCH((n) ==  8, rb_define_singleton_method_08, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_07(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_09(n) RBIMPL_ANYARGS_DISPATCH((n) ==  9, rb_define_singleton_method_09, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_08(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_singleton_method_10, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_09(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_singleton_method_11, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_10(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_singleton_method_12, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_11(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_singleton_method_13, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_12(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_singleton_method_14, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_13(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_singleton_method_15, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_14(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_m2(n) RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_protected_method_m2, rb_define_protected_method_m3)
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_m1(n) RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_protected_method_m1, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_m2(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_00(n) RBIMPL_ANYARGS_DISPATCH((n) ==  0, rb_define_protected_method_00, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_m1(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_01(n) RBIMPL_ANYARGS_DISPATCH((n) ==  1, rb_define_protected_method_01, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_00(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_02(n) RBIMPL_ANYARGS_DISPATCH((n) ==  2, rb_define_protected_method_02, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_01(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_03(n) RBIMPL_ANYARGS_DISPATCH((n) ==  3, rb_define_protected_method_03, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_02(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_04(n) RBIMPL_ANYARGS_DISPATCH((n) ==  4, rb_define_protected_method_04, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_03(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_05(n) RBIMPL_ANYARGS_DISPATCH((n) ==  5, rb_define_protected_method_05, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_04(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_06(n) RBIMPL_ANYARGS_DISPATCH((n) ==  6, rb_define_protected_method_06, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_05(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_07(n) RBIMPL_ANYARGS_DISPATCH((n) ==  7, rb_define_protected_method_07, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_06(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_08(n) RBIMPL_ANYARGS_DISPATCH((n) ==  8, rb_define_protected_method_08, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_07(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_09(n) RBIMPL_ANYARGS_DISPATCH((n) ==  9, rb_define_protected_method_09, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_08(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_10(n) RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_protected_method_10, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_09(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_11(n) RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_protected_method_11, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_10(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_12(n) RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_protected_method_12, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_11(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_13(n) RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_protected_method_13, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_12(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_14(n) RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_protected_method_14, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_13(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_15(n) RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_protected_method_15, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_14(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_m2(n)   RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_private_method_m2,   rb_define_private_method_m3)
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_m1(n)   RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_private_method_m1,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_m2(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_00(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  0, rb_define_private_method_00,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_m1(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_01(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  1, rb_define_private_method_01,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_00(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_02(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  2, rb_define_private_method_02,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_01(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_03(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  3, rb_define_private_method_03,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_02(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_04(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  4, rb_define_private_method_04,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_03(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_05(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  5, rb_define_private_method_05,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_04(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_06(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  6, rb_define_private_method_06,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_05(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_07(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  7, rb_define_private_method_07,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_06(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_08(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  8, rb_define_private_method_08,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_07(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_09(n)   RBIMPL_ANYARGS_DISPATCH((n) ==  9, rb_define_private_method_09,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_08(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_10(n)   RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_private_method_10,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_09(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_11(n)   RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_private_method_11,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_10(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_12(n)   RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_private_method_12,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_11(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_13(n)   RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_private_method_13,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_12(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_14(n)   RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_private_method_14,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_13(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_15(n)   RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_private_method_15,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_14(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_m2(n)  RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_module_function_m2,  rb_define_module_function_m3)
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_m1(n)  RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_module_function_m1,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_m2(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_00(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  0, rb_define_module_function_00,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_m1(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_01(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  1, rb_define_module_function_01,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_00(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_02(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  2, rb_define_module_function_02,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_01(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_03(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  3, rb_define_module_function_03,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_02(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_04(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  4, rb_define_module_function_04,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_03(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_05(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  5, rb_define_module_function_05,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_04(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_06(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  6, rb_define_module_function_06,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_05(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_07(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  7, rb_define_module_function_07,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_06(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_08(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  8, rb_define_module_function_08,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_07(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_09(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  9, rb_define_module_function_09,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_08(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_10(n)  RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_module_function_10,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_09(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_11(n)  RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_module_function_11,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_10(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_12(n)  RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_module_function_12,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_11(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_13(n)  RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_module_function_13,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_12(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_14(n)  RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_module_function_14,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_13(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_15(n)  RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_module_function_15,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_14(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_m2(n)  RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_global_function_m2,  rb_define_global_function_m3)
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_m1(n)  RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_global_function_m1,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_m2(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_00(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  0, rb_define_global_function_00,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_m1(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_01(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  1, rb_define_global_function_01,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_00(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_02(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  2, rb_define_global_function_02,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_01(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_03(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  3, rb_define_global_function_03,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_02(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_04(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  4, rb_define_global_function_04,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_03(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_05(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  5, rb_define_global_function_05,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_04(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_06(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  6, rb_define_global_function_06,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_05(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_07(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  7, rb_define_global_function_07,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_06(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_08(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  8, rb_define_global_function_08,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_07(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_09(n)  RBIMPL_ANYARGS_DISPATCH((n) ==  9, rb_define_global_function_09,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_08(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_10(n)  RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_global_function_10,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_09(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_11(n)  RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_global_function_11,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_10(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_12(n)  RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_global_function_12,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_11(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_13(n)  RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_global_function_13,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_12(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_14(n)  RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_global_function_14,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_13(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_15(n)  RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_global_function_15,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_14(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_m2(n)        RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_method_id_m2,        rb_define_method_id_m3)
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_m1(n)        RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_method_id_m1,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_m2(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_00(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  0, rb_define_method_id_00,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_m1(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_01(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  1, rb_define_method_id_01,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_00(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_02(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  2, rb_define_method_id_02,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_01(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_03(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  3, rb_define_method_id_03,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_02(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_04(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  4, rb_define_method_id_04,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_03(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_05(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  5, rb_define_method_id_05,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_04(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_06(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  6, rb_define_method_id_06,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_05(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_07(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  7, rb_define_method_id_07,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_06(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_08(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  8, rb_define_method_id_08,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_07(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_09(n)        RBIMPL_ANYARGS_DISPATCH((n) ==  9, rb_define_method_id_09,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_08(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_10(n)        RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_method_id_10,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_09(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_11(n)        RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_method_id_11,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_10(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_12(n)        RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_method_id_12,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_11(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_13(n)        RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_method_id_13,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_12(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_14(n)        RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_method_id_14,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_13(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_15(n)        RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_method_id_15,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_14(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_m2(n)           RBIMPL_ANYARGS_DISPATCH((n) == -2, rb_define_method_m2,           rb_define_method_m3)
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_m1(n)           RBIMPL_ANYARGS_DISPATCH((n) == -1, rb_define_method_m1,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_m2(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_00(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  0, rb_define_method_00,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_m1(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_01(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  1, rb_define_method_01,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_00(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_02(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  2, rb_define_method_02,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_01(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_03(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  3, rb_define_method_03,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_02(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_04(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  4, rb_define_method_04,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_03(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_05(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  5, rb_define_method_05,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_04(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_06(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  6, rb_define_method_06,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_05(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_07(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  7, rb_define_method_07,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_06(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_08(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  8, rb_define_method_08,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_07(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_09(n)           RBIMPL_ANYARGS_DISPATCH((n) ==  9, rb_define_method_09,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_08(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_10(n)           RBIMPL_ANYARGS_DISPATCH((n) == 10, rb_define_method_10,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_09(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_11(n)           RBIMPL_ANYARGS_DISPATCH((n) == 11, rb_define_method_11,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_10(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_12(n)           RBIMPL_ANYARGS_DISPATCH((n) == 12, rb_define_method_12,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_11(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_13(n)           RBIMPL_ANYARGS_DISPATCH((n) == 13, rb_define_method_13,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_12(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_14(n)           RBIMPL_ANYARGS_DISPATCH((n) == 14, rb_define_method_14,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_13(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_15(n)           RBIMPL_ANYARGS_DISPATCH((n) == 15, rb_define_method_15,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_14(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method(n, f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_singleton_method_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method_15(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method(n, f) RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_protected_method_m3, RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method_15(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_private_method(n, f)   RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_private_method_m3,   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method_15(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_module_function(n, f)  RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_module_function_m3,  RBIMPL_ANYARGS_DISPATCH_rb_define_module_function_15(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_global_function(n, f)  RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_global_function_m3,  RBIMPL_ANYARGS_DISPATCH_rb_define_global_function_15(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method_id(n, f)        RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_method_id_m3,        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id_15(n))
# define RBIMPL_ANYARGS_DISPATCH_rb_define_method(n, f)           RBIMPL_ANYARGS_DISPATCH(RBIMPL_CFUNC_IS_rb_f_notimplement(f), rb_define_method_m3,           RBIMPL_ANYARGS_DISPATCH_rb_define_method_15(n))
# define RBIMPL_ANYARGS_ATTRSET(sym) RBIMPL_ATTR_MAYBE_UNUSED() RBIMPL_ATTR_NONNULL(()) RBIMPL_ATTR_WEAKREF(sym)
# define RBIMPL_ANYARGS_DECL(sym, ...) \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _m3(__VA_ARGS__, VALUE(*)(ANYARGS), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _m2(__VA_ARGS__, VALUE(*)(VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _m1(__VA_ARGS__, VALUE(*)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _00(__VA_ARGS__, VALUE(*)(VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _01(__VA_ARGS__, VALUE(*)(VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _02(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _03(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _04(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _05(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _06(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _07(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _08(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _09(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _10(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _11(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _12(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _13(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _14(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int); \
RBIMPL_ANYARGS_ATTRSET(sym) static void sym ## _15(__VA_ARGS__, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE), int);
RBIMPL_ANYARGS_DECL(rb_define_singleton_method, VALUE, const char *)
RBIMPL_ANYARGS_DECL(rb_define_protected_method, VALUE, const char *)
RBIMPL_ANYARGS_DECL(rb_define_private_method, VALUE, const char *)
RBIMPL_ANYARGS_DECL(rb_define_module_function, VALUE, const char *)
RBIMPL_ANYARGS_DECL(rb_define_global_function, const char *)
RBIMPL_ANYARGS_DECL(rb_define_method_id, VALUE, ID)
RBIMPL_ANYARGS_DECL(rb_define_method, VALUE, const char *)
/** @endcond */

/**
 * @brief  Defines klass\#mid.
 * @see    ::rb_define_method
 * @param  klass  Where the method lives.
 * @param  mid    Name of the defining method.
 * @param  func   Implementation of klass\#mid.
 * @param  arity  Arity of klass\#mid.
 */
#define rb_define_method(klass, mid, func, arity)           RBIMPL_ANYARGS_DISPATCH_rb_define_method((arity), (func))((klass), (mid), (func), (arity))

/**
 * @brief  Defines klass\#mid.
 * @see    ::rb_define_method_id
 * @param  klass  Where the method lives.
 * @param  mid    Name of the defining method.
 * @param  func   Implementation of klass\#mid.
 * @param  arity  Arity of klass\#mid.
 */
#define rb_define_method_id(klass, mid, func, arity)        RBIMPL_ANYARGS_DISPATCH_rb_define_method_id((arity), (func))((klass), (mid), (func), (arity))

/**
 * @brief  Defines obj.mid.
 * @see    ::rb_define_singleton_method
 * @param  obj    Where the method lives.
 * @param  mid    Name of the defining method.
 * @param  func   Implementation of obj.mid.
 * @param  arity  Arity of obj.mid.
 */
#define rb_define_singleton_method(obj, mid, func, arity)   RBIMPL_ANYARGS_DISPATCH_rb_define_singleton_method((arity), (func))((obj), (mid), (func), (arity))

/**
 * @brief  Defines klass\#mid and make it protected.
 * @see    ::rb_define_protected_method
 * @param  klass  Where the method lives.
 * @param  mid    Name of the defining method.
 * @param  func   Implementation of klass\#mid.
 * @param  arity  Arity of klass\#mid.
 */
#define rb_define_protected_method(klass, mid, func, arity) RBIMPL_ANYARGS_DISPATCH_rb_define_protected_method((arity), (func))((klass), (mid), (func), (arity))

/**
 * @brief  Defines klass\#mid and make it private.
 * @see    ::rb_define_private_method
 * @param  klass  Where the method lives.
 * @param  mid    Name of the defining method.
 * @param  func   Implementation of klass\#mid.
 * @param  arity  Arity of klass\#mid.
 */
#define rb_define_private_method(klass, mid, func, arity)   RBIMPL_ANYARGS_DISPATCH_rb_define_private_method((arity), (func))((klass), (mid), (func), (arity))

/**
 * @brief  Defines mod\#mid and make it a module function.
 * @see    ::rb_define_module_function
 * @param  mod    Where the method lives.
 * @param  mid    Name of the defining method.
 * @param  func   Implementation of mod\#mid.
 * @param  arity  Arity of mod\#mid.
 */
#define rb_define_module_function(mod, mid, func, arity)    RBIMPL_ANYARGS_DISPATCH_rb_define_module_function((arity), (func))((mod), (mid), (func), (arity))

/**
 * @brief  Defines ::rb_mKerbel \#mid.
 * @see    ::rb_define_global_function
 * @param  mid    Name of the defining method.
 * @param  func   Implementation of ::rb_mKernel \#mid.
 * @param  arity  Arity of ::rb_mKernel \#mid.
 */
#define rb_define_global_function(mid, func, arity)         RBIMPL_ANYARGS_DISPATCH_rb_define_global_function((arity), (func))((mid), (func), (arity))

#endif /* __cplusplus */

/**
 * This  macro is  to properly  cast  a function  parameter of  *_define_method
 * family.  It  has been  around since  1.x era so  you can  maximise backwards
 * compatibility by using it.
 *
 * ```CXX
 * rb_define_method(klass, "method", RUBY_METHOD_FUNC(func), arity);
 * ```
 *
 * @param  func  A pointer to a function that implements a method.
 */
#if ! defined(RUBY_DEVEL)
# define RUBY_METHOD_FUNC(func) RBIMPL_CAST((VALUE (*)(ANYARGS))(func))

#elif ! RUBY_DEVEL
# define RUBY_METHOD_FUNC(func) RBIMPL_CAST((VALUE (*)(ANYARGS))(func))

#elif ! defined(rb_define_method)
# define RUBY_METHOD_FUNC(func) RBIMPL_CAST((VALUE (*)(ANYARGS))(func))

#else
# define RUBY_METHOD_FUNC(func) (func)

#endif

#endif /* RBIMPL_ANYARGS_H */
