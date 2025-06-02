#ifndef RUBY_BACKWARD2_ATTRIBUTES_H                  /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_BACKWARD2_ATTRIBUTES_H
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
 * @brief      Various attribute-related macros.
 *
 * ### Q&A ###
 *
 * - Q: Why  are the  macros defined  in this  header file  so inconsistent  in
 *      style?
 *
 * - A: Don't know.   Don't blame me.  Backward compatibility is  the key here.
 *      I'm just preserving what they have been.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/attr/alloc_size.h"
#include "ruby/internal/attr/cold.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/error.h"
#include "ruby/internal/attr/forceinline.h"
#include "ruby/internal/attr/format.h"
#include "ruby/internal/attr/maybe_unused.h"
#include "ruby/internal/attr/noinline.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/attr/restrict.h"
#include "ruby/internal/attr/returns_nonnull.h"
#include "ruby/internal/attr/warning.h"
#include "ruby/internal/has/attribute.h"

/* function attributes */
#undef CONSTFUNC
#define CONSTFUNC(x) RBIMPL_ATTR_CONST() x

#undef PUREFUNC
#define PUREFUNC(x) RBIMPL_ATTR_PURE() x

#undef DEPRECATED
#define DEPRECATED(x) RBIMPL_ATTR_DEPRECATED(("")) x

#undef DEPRECATED_BY
#define DEPRECATED_BY(n,x) RBIMPL_ATTR_DEPRECATED(("by: " # n)) x

#undef DEPRECATED_TYPE
#if defined(__GNUC__)
# define DEPRECATED_TYPE(mesg, decl)                      \
    _Pragma("message \"DEPRECATED_TYPE is deprecated\""); \
    decl RBIMPL_ATTR_DEPRECATED(mseg)
#elif defined(_MSC_VER)
# pragma deprecated(DEPRECATED_TYPE)
# define DEPRECATED_TYPE(mesg, decl)                              \
    __pragma(message(__FILE__"("STRINGIZE(__LINE__)"): warning: " \
                     "DEPRECATED_TYPE is deprecated"))            \
    decl RBIMPL_ATTR_DEPRECATED(mseg)
#else
# define DEPRECATED_TYPE(mesg, decl)                    \
    <-<-"DEPRECATED_TYPE is deprecated"->->
#endif

#undef RUBY_CXX_DEPRECATED
#define RUBY_CXX_DEPRECATED(mseg) RBIMPL_ATTR_DEPRECATED((mseg))

#undef NOINLINE
#define NOINLINE(x) RBIMPL_ATTR_NOINLINE() x

#ifndef MJIT_HEADER
# undef ALWAYS_INLINE
# define ALWAYS_INLINE(x) RBIMPL_ATTR_FORCEINLINE() x
#endif

#undef ERRORFUNC
#define ERRORFUNC(mesg, x) RBIMPL_ATTR_ERROR(mesg) x
#if RBIMPL_HAS_ATTRIBUTE(error)
# define HAVE_ATTRIBUTE_ERRORFUNC 1
#endif

#undef WARNINGFUNC
#define WARNINGFUNC(mesg, x) RBIMPL_ATTR_WARNING(mesg) x
#if RBIMPL_HAS_ATTRIBUTE(warning)
# define HAVE_ATTRIBUTE_WARNINGFUNC 1
#endif

/*
  cold attribute for code layout improvements
  RUBY_FUNC_ATTRIBUTE not used because MSVC does not like nested func macros
 */
#undef COLDFUNC
#define COLDFUNC RBIMPL_ATTR_COLD()

#define PRINTF_ARGS(decl, string_index, first_to_check) \
    RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, (string_index), (first_to_check)) \
    decl

#undef RUBY_ATTR_ALLOC_SIZE
#define RUBY_ATTR_ALLOC_SIZE RBIMPL_ATTR_ALLOC_SIZE

#undef RUBY_ATTR_MALLOC
#define RUBY_ATTR_MALLOC RBIMPL_ATTR_RESTRICT()

#undef RUBY_ATTR_RETURNS_NONNULL
#define RUBY_ATTR_RETURNS_NONNULL RBIMPL_ATTR_RETURNS_NONNULL()

#ifndef FUNC_MINIMIZED
#define FUNC_MINIMIZED(x) x
#endif

#ifndef FUNC_UNOPTIMIZED
#define FUNC_UNOPTIMIZED(x) x
#endif

#ifndef RUBY_ALIAS_FUNCTION_TYPE
#define RUBY_ALIAS_FUNCTION_TYPE(type, prot, name, args) \
    FUNC_MINIMIZED(type prot) {return (type)name args;}
#endif

#ifndef RUBY_ALIAS_FUNCTION_VOID
#define RUBY_ALIAS_FUNCTION_VOID(prot, name, args) \
    FUNC_MINIMIZED(void prot) {name args;}
#endif

#ifndef RUBY_ALIAS_FUNCTION
#define RUBY_ALIAS_FUNCTION(prot, name, args) \
    RUBY_ALIAS_FUNCTION_TYPE(VALUE, prot, name, args)
#endif

#undef RUBY_FUNC_NONNULL
#define RUBY_FUNC_NONNULL(n, x) RBIMPL_ATTR_NONNULL(n) x

#undef  NORETURN
#define NORETURN(x) RBIMPL_ATTR_NORETURN() x
#define NORETURN_STYLE_NEW

#ifndef PACKED_STRUCT
# define PACKED_STRUCT(x) x
#endif

#ifndef PACKED_STRUCT_UNALIGNED
# if UNALIGNED_WORD_ACCESS
#   define PACKED_STRUCT_UNALIGNED(x) PACKED_STRUCT(x)
# else
#   define PACKED_STRUCT_UNALIGNED(x) x
# endif
#endif

#undef RB_UNUSED_VAR
#define RB_UNUSED_VAR(x) x RBIMPL_ATTR_MAYBE_UNUSED()

#endif /* RUBY_BACKWARD2_ATTRIBUTES_H */
