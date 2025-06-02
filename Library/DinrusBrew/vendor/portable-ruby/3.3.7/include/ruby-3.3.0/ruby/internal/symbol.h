#ifndef RBIMPL_SYMBOL_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_SYMBOL_H
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
 * @brief      Defines #rb_intern
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#endif

#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/constant_p.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/has/builtin.h"
#include "ruby/internal/value.h"

#define RB_ID2SYM      rb_id2sym           /**< @alias{rb_id2sym} */
#define RB_SYM2ID      rb_sym2id           /**< @alias{rb_sym2id} */
#define ID2SYM         RB_ID2SYM           /**< @old{RB_ID2SYM} */
#define SYM2ID         RB_SYM2ID           /**< @old{RB_SYM2ID} */
#define CONST_ID_CACHE RUBY_CONST_ID_CACHE /**< @old{RUBY_CONST_ID_CACHE} */
#define CONST_ID       RUBY_CONST_ID       /**< @old{RUBY_CONST_ID} */

/** @cond INTERNAL_MACRO */
#define rb_intern_const rb_intern_const
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Converts an instance of ::rb_cSymbol into an ::ID.
 *
 * @param[in]  obj            An instance of ::rb_cSymbol.
 * @exception  rb_eTypeError  `obj` is not an instance of ::rb_cSymbol.
 * @return     An ::ID of the identical symbol.
 */
ID rb_sym2id(VALUE obj);

/**
 * Allocates an instance of ::rb_cSymbol that has the given id.
 *
 * @param[in]  id           An id.
 * @retval     RUBY_Qfalse  No such id ever existed in the history.
 * @retval     Otherwise    An allocated ::rb_cSymbol instance.
 */
VALUE rb_id2sym(ID id);

RBIMPL_ATTR_NONNULL(())
/**
 * Finds or creates a symbol of the given name.
 *
 * @param[in]  name              The name of the id.
 * @exception  rb_eRuntimeError  Too many symbols.
 * @return     A (possibly new) id whose value is the given name.
 * @note       These days  Ruby internally has  two kinds of symbols  (static /
 *             dynamic).  Symbols  created using  this function would  become a
 *             static one; i.e. would never be  garbage collected.  It is up to
 *             you to avoid memory leaks.  Think twice before using it.
 */
ID rb_intern(const char *name);

/**
 * Identical to  rb_intern(), except  it additionally takes  the length  of the
 * string.  This way you can have a symbol that contains NUL characters.
 *
 * @param[in]  name              The name of the id.
 * @param[in]  len               Length of `name`.
 * @exception  rb_eRuntimeError  Too many symbols.
 * @return     A (possibly new) id whose value is the given name.
 * @note       These   days  Ruby   internally   has  two   kinds  of   symbols
 *             (static/dynamic).   Symbols created  using  this function  would
 *             become static ones;  i.e. would never be  garbage collected.  It
 *             is up  to you to avoid  memory leaks.  Think twice  before using
 *             it.
 */
ID rb_intern2(const char *name, long len);

/**
 * Identical to  rb_intern(), except  it takes an instance of ::rb_cString.
 *
 * @param[in]  str               The name of the id.
 * @pre        `str` must either be an instance of ::rb_cSymbol, or an instance
 *             of ::rb_cString, or responds to `#to_str` method.
 * @exception  rb_eTypeError     Can't convert `str` into ::rb_cString.
 * @exception  rb_eRuntimeError  Too many symbols.
 * @return     A (possibly new) id whose value is the given str.
 * @note       These   days  Ruby   internally   has  two   kinds  of   symbols
 *             (static/dynamic).   Symbols created  using  this function  would
 *             become static ones;  i.e. would never be  garbage collected.  It
 *             is up  to you to avoid  memory leaks.  Think twice  before using
 *             it.
 */
ID rb_intern_str(VALUE str);

/**
 * Retrieves the name mapped to the given id.
 *
 * @param[in]  id         An id to query.
 * @retval     NULL       No such id ever existed in the history.
 * @retval     otherwise  A name that the id represents.
 * @note       The return value  is managed by the interpreter.   Don't pass it
 *             to free().
 */
const char *rb_id2name(ID id);

RBIMPL_ATTR_NONNULL(())
/**
 * Detects if  the given name  is already interned or  not.  It first  tries to
 * convert the  argument to  an instance  of ::rb_cString if  it is  neither an
 * instance of ::rb_cString nor ::rb_cSymbol.  The conversion result is written
 * back  to the  variable.   Then queries  if that  name  was already  interned
 * before.  If found it returns such id, otherwise zero.
 *
 * We  eventually introduced  this API  to avoid  inadvertent symbol  pin-down.
 * Before,  there was  no way  to know  if an  ID was  already interned  or not
 * without actually  creating one (== leaking  memory).  By using this  API you
 * can avoid such situations:
 *
 * ```CXX
 * bool does_interning_this_leak_memory(VALUE obj)
 * {
 *     auto tmp = obj;
 *     if (auto id = rb_check_id(&tmp); id) {
 *         return false;
 *     }
 *     else {
 *         return true; // Let GC sweep tmp if necessary.
 *     }
 * }
 * ```
 *
 * @param[in,out]  namep              A pointer to a name to query.
 * @pre            The object referred  by `*namep` must either  be an instance
 *                 of ::rb_cSymbol, or an instance of ::rb_cString, or responds
 *                 to `#to_str` method.
 * @exception      rb_eTypeError      Can't convert `*namep` into ::rb_cString.
 * @exception      rb_eEncodingError  Given string is non-ASCII.
 * @retval         0                  No such id ever existed in the history.
 * @retval         otherwise          The id that represents the given name.
 * @post           The object  that `*namep`  points to  is a  converted result
 *                 object, which  is always an instance  of either ::rb_cSymbol
 *                 or ::rb_cString.
 * @see            https://bugs.ruby-lang.org/issues/5072
 *
 * @internal
 *
 * @shyouhei doesn't know why this has to raise rb_eEncodingError.
 */
ID rb_check_id(volatile VALUE *namep);

/**
 * @copydoc rb_intern_str()
 *
 * @internal
 *
 * :FIXME:  Can anyone  tell us  what is  the difference  between this  one and
 * rb_intern_str()?  As far as @shyouhei reads the implementation it seems what
 * rb_to_id() does is  is just waste some CPU time,  then call rb_intern_str().
 * He hopes he is wrong.
 */
ID rb_to_id(VALUE str);

/**
 * Identical to rb_id2name(), except it returns a Ruby's String instead of C's.
 *
 * @param[in]  id           An id to query.
 * @retval     RUBY_Qfalse  No such id ever existed in the history.
 * @retval     otherwise    An instance of ::rb_cString with the name of id.
 *
 * @internal
 *
 * In reality "rb_id2str() is identical  to rb_id2name() except it returns Ruby
 * string" is just describing things upside down; truth is `rb_id2name(foo)` is
 * a shorthand of `RSTRING_PTR(rb_id2str(foo))`.
 */
VALUE rb_id2str(ID id);

/**
 * Identical to rb_id2str(), except it takes an instance of ::rb_cSymbol rather
 * than an ::ID.
 *
 * @param[in]  id           An id to query.
 * @retval     RUBY_Qfalse  No such id ever existed in the history.
 * @retval     otherwise    An instance of ::rb_cString with the name of id.
 */
VALUE rb_sym2str(VALUE id);

/**
 * Identical  to  rb_intern_str(), except  it  generates  a dynamic  symbol  if
 * necessary.
 *
 * @param[in]  name              The name of the id.
 * @pre        `name`  must  either  be  an instance  of  ::rb_cSymbol,  or  an
 *             instance of ::rb_cString, or responds to `#to_str` method.
 * @exception  rb_eTypeError     Can't convert `name` into ::rb_cString.
 * @exception  rb_eRuntimeError  Too many symbols.
 * @return     A (possibly new) id whose value is the given name.
 * @note       These   days  Ruby   internally   has  two   kinds  of   symbols
 *             (static/dynamic).   Symbols created  using  this function  would
 *             become dynamic ones; i.e. would  be garbage collected.  It could
 *             be safer for you to use it than alternatives, when applicable.
 */
VALUE rb_to_symbol(VALUE name);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to  rb_check_id(), except it  returns an instance  of ::rb_cSymbol
 * instead.
 *
 * @param[in,out]  namep              A pointer to a name to query.
 * @pre            The object referred  by `*namep` must either  be an instance
 *                 of ::rb_cSymbol, or an instance of ::rb_cString, or responds
 *                 to `#to_str` method.
 * @exception      rb_eTypeError      Can't convert `*namep` into ::rb_cString.
 * @exception      rb_eEncodingError  Given string is non-ASCII.
 * @retval         RUBY_Qnil          No such id ever existed in the history.
 * @retval         otherwise          The id that represents the given name.
 * @post           The object  that `*namep`  points to  is a  converted result
 *                 object, which  is always an instance  of either ::rb_cSymbol
 *                 or ::rb_cString.
 * @see            https://bugs.ruby-lang.org/issues/5072
 *
 * @internal
 *
 * @shyouhei doesn't know why this has to raise rb_eEncodingError.
 */
VALUE rb_check_symbol(volatile VALUE *namep);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE()
RBIMPL_ATTR_NONNULL(())
/**
 * This  is a  "tiny  optimisation" over  rb_intern().  If  you  pass a  string
 * _literal_, and if your C compiler can special-case strlen of such literal to
 * strength-reduce  into  an  integer  constant expression,  then  this  inline
 * function can precalc a part of conversion.
 *
 * @note       This function also works  happily for non-constant strings.  Why
 *             bother then?  Just apply liberally to everything.
 * @note       But  #rb_intern() could  be faster  on compilers  with statement
 *             expressions, because they can cache the created ::ID.
 * @param[in]  str               The name of the id.
 * @exception  rb_eRuntimeError  Too many symbols.
 * @return     A (possibly new) id whose value is the given str.
 * @note       These days  Ruby internally has  two kinds of symbols  (static /
 *             dynamic).  Symbols  created using  this function would  become a
 *             static one; i.e. would never be  garbage collected.  It is up to
 *             you to avoid memory leaks.  Think twice before using it.
 */
static inline ID
rb_intern_const(const char *str)
{
    size_t len = strlen(str);
    return rb_intern2(str, RBIMPL_CAST((long)len));
}

RBIMPL_ATTR_NOALIAS()
RBIMPL_ATTR_NONNULL(())
/**
 * @private
 *
 * This is an implementation detail of #rb_intern().  Just don't use it.
 */
static inline ID
rbimpl_intern_const(ID *ptr, const char *str)
{
    while (! *ptr) {
        *ptr = rb_intern_const(str);
    }

    return *ptr;
}

/**
 * Old implementation detail of rb_intern().
 * @deprecated Does anyone use it?  Preserved for backward compat.
 */
#define RUBY_CONST_ID_CACHE(result, str)                \
    {                                                   \
        static ID rb_intern_id_cache;                   \
        rbimpl_intern_const(&rb_intern_id_cache, (str)); \
        result rb_intern_id_cache;                      \
    }

/**
 * Old implementation detail of rb_intern().
 * @deprecated Does anyone use it?  Preserved for backward compat.
 */
#define RUBY_CONST_ID(var, str) \
    do { \
        static ID rbimpl_id; \
        (var) = rbimpl_intern_const(&rbimpl_id, (str)); \
    } while (0)

#if defined(HAVE_STMT_AND_DECL_IN_EXPR)
/* __builtin_constant_p and statement expression is available
 * since gcc-2.7.2.3 at least. */
#define rb_intern(str) \
    (RBIMPL_CONSTANT_P(str) ? \
     __extension__ ({ \
         static ID rbimpl_id; \
         rbimpl_intern_const(&rbimpl_id, (str)); \
     }) : \
     (rb_intern)(str))
#endif

#endif /* RBIMPL_SYMBOL_H */
