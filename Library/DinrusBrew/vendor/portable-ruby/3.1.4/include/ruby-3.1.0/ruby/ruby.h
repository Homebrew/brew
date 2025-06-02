#ifndef RUBY_RUBY_H                                  /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_RUBY_H 1
/**
 * @file
 * @author     $Author$
 * @date       Thu Jun 10 14:26:32 JST 1993
 * @copyright  Copyright (C) 1993-2008 Yukihiro Matsumoto
 * @copyright  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
 * @copyright  Copyright (C) 2000  Information-technology Promotion Agency, Japan
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/config.h"

/* @shyouhei  doesn't  understand  why  we need  <intrinsics.h>  at  this  very
 * beginning of the entire <ruby.h> circus. */
#ifdef HAVE_INTRINSICS_H
# include <intrinsics.h>
#endif

#include <stdarg.h>

#include "defines.h"
#include "ruby/internal/anyargs.h"
#include "ruby/internal/arithmetic.h"
#include "ruby/internal/core.h"
#include "ruby/internal/ctype.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/error.h"
#include "ruby/internal/eval.h"
#include "ruby/internal/event.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/gc.h"
#include "ruby/internal/glob.h"
#include "ruby/internal/globals.h"
#include "ruby/internal/has/warning.h"
#include "ruby/internal/interpreter.h"
#include "ruby/internal/iterator.h"
#include "ruby/internal/memory.h"
#include "ruby/internal/method.h"
#include "ruby/internal/module.h"
#include "ruby/internal/newobj.h"
#include "ruby/internal/rgengc.h"
#include "ruby/internal/scan_args.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/symbol.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/internal/variable.h"
#include "ruby/assert.h"
#include "ruby/backward/2/assume.h"
#include "ruby/backward/2/inttypes.h"
#include "ruby/backward/2/limits.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* Module#methods, #singleton_methods and so on return Symbols */
/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define USE_SYMBOL_AS_METHOD_NAME 1

/**
 * Converts an object to a path.  It first tries `#to_path` method if any, then
 * falls back to `#to_str` method.
 *
 * @param[in]  obj                 Arbitrary ruby object.
 * @exception  rb_eArgError        `obj` contains a NUL byte.
 * @exception  rb_eTypeError       `obj` is not path-ish.
 * @exception  rb_eEncCompatError  No encoding conversion from `obj` to path.
 * @return     Converted path object.
 */
VALUE rb_get_path(VALUE obj);

/**
 * Ensures that the parameter object is a path.
 *
 * @param[in,out]  v                   Arbitrary ruby object.
 * @exception      rb_eArgError        `v` contains a NUL byte.
 * @exception      rb_eTypeError       `v` is not path-ish.
 * @exception      rb_eEncCompatError  `v` is not path-compatible.
 * @post           `v` is a path.
 */
#define FilePathValue(v) (RB_GC_GUARD(v) = rb_get_path(v))

/**
 * @deprecated  This function is an alias  of rb_get_path() now.  The part that
 *              did "no_checksafe" was deleted.  It  remains here because of no
 *              harm.
 */
VALUE rb_get_path_no_checksafe(VALUE);

/**
 * @deprecated  This macro is an alias of #FilePathValue now.  The part that did
 *              "String" was deleted.  It remains here because of no harm.
 */
#define FilePathStringValue(v) ((v) = rb_get_path(v))

/** @cond INTERNAL_MACRO */
#if defined(HAVE_BUILTIN___BUILTIN_CONSTANT_P) && defined(HAVE_STMT_AND_DECL_IN_EXPR)
# define rb_varargs_argc_check_runtime(argc, vargc) \
    (((argc) <= (vargc)) ? (argc) : \
     (rb_fatal("argc(%d) exceeds actual arguments(%d)", \
	       argc, vargc), 0))
# define rb_varargs_argc_valid_p(argc, vargc) \
    ((argc) == 0 ? (vargc) <= 1 : /* [ruby-core:85266] [Bug #14425] */ \
     (argc) == (vargc))
# if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
#   ifdef HAVE_ATTRIBUTE_ERRORFUNC
ERRORFUNC((" argument length doesn't match"), int rb_varargs_bad_length(int,int));
#   else
#     define rb_varargs_bad_length(argc, vargc) \
	((argc)/rb_varargs_argc_valid_p(argc, vargc))
#   endif
#   define rb_varargs_argc_check(argc, vargc) \
    __builtin_choose_expr(__builtin_constant_p(argc), \
	(rb_varargs_argc_valid_p(argc, vargc) ? (argc) : \
	 rb_varargs_bad_length(argc, vargc)), \
	rb_varargs_argc_check_runtime(argc, vargc))
# else
#   define rb_varargs_argc_check(argc, vargc) \
	rb_varargs_argc_check_runtime(argc, vargc)
# endif
#endif
/** @endcond */

/**
 * Queries the name of the passed class.
 *
 * @param[in]  klass  An instance of a class.
 * @return     The name of `klass`.
 * @note       Return value is managed by our GC.  Don't free.
 */
const char *rb_class2name(VALUE klass);

/**
 * Queries the name of the class of the passed object.
 *
 * @param[in]  obj  Arbitrary ruby object.
 * @return     The name of the class of `obj`.
 * @note       Return value is managed by our GC.  Don't free.
 */
const char *rb_obj_classname(VALUE obj);

/**
 * Inspects an object.   It first calls the argument's  `#inspect` method, then
 * feeds its result string into ::rb_stdout.
 *
 * This is identical to Ruby level `Kernel#p`, except it takes only one object.
 *
 * @internal
 *
 * Above description is in fact inaccurate.  This API interfaces with Ractors.
 */
void rb_p(VALUE obj);

/**
 * This function is an optimised version  of calling `#==`.  It checks equality
 * between two  objects by first  doing a fast  identity check using  using C's
 * `==` (same  as `BasicObject#equal?`).  If  that check fails, it  calls `#==`
 * dynamically.   This optimisation  actually affects  semantics, because  when
 * `#==`  returns false  for the  same object  obj, `rb_equal(obj,  obj)` would
 * still  return true.   This happens  for `Float::NAN`,  where `Float::NAN  ==
 * Float::NAN` is `false`, but `rb_equal(Float::NAN, Float::NAN)` is `true`.
 *
 * @param[in]  lhs          Comparison LHS.
 * @param[in]  rhs          Comparison RHS.
 * @retval     RUBY_Qtrue   They are the same.
 * @retval     RUBY_Qfalse  They are different.
 */
VALUE rb_equal(VALUE lhs, VALUE rhs);

/**
 * Identical  to rb_require_string(),  except it  takes C's  string instead  of
 * Ruby's.
 *
 * @param[in]  feature           Name of a feature, e.g. `"json"`.
 * @exception  rb_eLoadError     No such feature.
 * @exception  rb_eRuntimeError  `$"` is frozen; unable to push.
 * @retval     RUBY_Qtrue        The feature is loaded for the first time.
 * @retval     RUBY_Qfalse       The feature has already been loaded.
 * @post       `$"` is updated.
 */
VALUE rb_require(const char *feature);

#include "ruby/intern.h"

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define RUBY_VM 1 /* YARV */

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define HAVE_NATIVETHREAD

/**
 * Queries  if  the thread  which  calls  this  function  is a  ruby's  thread.
 * "Ruby's" in  this context  is a thread  created using one  of our  APIs like
 * rb_thread_create().   There  are  distinctions   between  ruby's  and  other
 * threads.  For instance calling ruby methods  are allowed only from inside of
 * a ruby's thread.
 *
 * @retval  1  The current thread is a Ruby's thread.
 * @retval  0  The current thread is a random thread from outside of Ruby.
 */
int ruby_native_thread_p(void);

/**
 * @private
 *
 * This macro is for internal use.  Must be a mistake to place here.
 */
#define InitVM(ext) {void InitVM_##ext(void);InitVM_##ext();}

RBIMPL_ATTR_NONNULL((3))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 3, 4)
/**
 * Our own locale-insensitive version of `snprintf(3)`.  It can also be seen as
 * a routine  identical to rb_sprintf(),  except it  writes back to  the passed
 * buffer instead of allocating a new Ruby object.
 *
 * @param[out]  str  Return buffer
 * @param[in]   n    Number of bytes of `str`.
 * @param[in]   fmt  A `printf`-like format specifier.
 * @param[in]   ...  Variadic number of contents to format.
 * @return      Number of bytes  that would have been written to  `str`, if `n`
 *              was large enough.  Comparing this  to `n` can give you insights
 *              that the buffer is too small  or too big.  Especially passing 0
 *              to `n`  gives you the exact  number of bytes necessary  to hold
 *              the result string without writing anything to anywhere.
 * @post        `str` holds  up to `n-1`  bytes of formatted contents  (and the
 *              terminating NUL character.)
 */
int ruby_snprintf(char *str, size_t n, char const *fmt, ...);

RBIMPL_ATTR_NONNULL((3))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 3, 0)
/**
 * Identical to ruby_snprintf(),  except it takes a `va_list`.  It  can also be
 * seen as a  routine identical to rb_vsprintf(), except it  writes back to the
 * passed buffer instead of allocating a new Ruby object.
 *
 * @param[out]  str  Return buffer
 * @param[in]   n    Number of bytes of `str`.
 * @param[in]   fmt  A `printf`-like format specifier.
 * @param[in]   ap   Contents  to format.
 * @return      Number of bytes  that would have been written to  `str`, if `n`
 *              was large enough.  Comparing this  to `n` can give you insights
 *              that the buffer is too small  or too big.  Especially passing 0
 *              to `n`  gives you the exact  number of bytes necessary  to hold
 *              the result string without writing anything to anywhere.
 * @post        `str` holds  up to `n-1`  bytes of formatted contents  (and the
 *              terminating NUL character.)
 */
int ruby_vsnprintf(char *str, size_t n, char const *fmt, va_list ap);

/** @cond INTERNAL_MACRO */
#if RBIMPL_HAS_WARNING("-Wgnu-zero-variadic-macro-arguments")
# /* Skip it; clang -pedantic doesn't like the following */
#elif defined(__GNUC__) && defined(HAVE_VA_ARGS_MACRO) && defined(__OPTIMIZE__)
# define rb_yield_values(argc, ...) \
__extension__({ \
	const int rb_yield_values_argc = (argc); \
	const VALUE rb_yield_values_args[] = {__VA_ARGS__}; \
	const int rb_yield_values_nargs = \
	    (int)(sizeof(rb_yield_values_args) / sizeof(VALUE)); \
	rb_yield_values2( \
	    rb_varargs_argc_check(rb_yield_values_argc, rb_yield_values_nargs), \
	    rb_yield_values_nargs ? rb_yield_values_args : NULL); \
    })

# define rb_funcall(recv, mid, argc, ...) \
__extension__({ \
	const int rb_funcall_argc = (argc); \
	const VALUE rb_funcall_args[] = {__VA_ARGS__}; \
	const int rb_funcall_nargs = \
	    (int)(sizeof(rb_funcall_args) / sizeof(VALUE)); \
        rb_funcallv(recv, mid, \
	    rb_varargs_argc_check(rb_funcall_argc, rb_funcall_nargs), \
	    rb_funcall_nargs ? rb_funcall_args : NULL); \
    })
#endif
/** @endcond */

#ifndef RUBY_DONT_SUBST
#include "ruby/subst.h"
#endif

#if !defined RUBY_EXPORT && !defined RUBY_NO_OLD_COMPATIBILITY
# include "ruby/backward.h"
#endif

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_RUBY_H */
