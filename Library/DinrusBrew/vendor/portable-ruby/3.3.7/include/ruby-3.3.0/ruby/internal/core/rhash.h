#ifndef RBIMPL_RHASH_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RHASH_H
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
 * @brief      Routines to manipulate struct RHash.
 * @note       The struct RHash itself is opaque.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#if !defined RUBY_EXPORT && !defined RUBY_NO_OLD_COMPATIBILITY
# include "ruby/backward.h"
#endif

/**
 * Retrieves the internal table.
 *
 * @param[in]  h  An instance of RHash.
 * @pre        `h` must be of ::RUBY_T_HASH.
 * @return     A struct st_table which has the contents of this hash.
 * @note       Nowadays as Ruby  evolved over ages, RHash  has multiple backend
 *             storage  engines.   `h`'s backend  is  not  guaranteed to  be  a
 *             st_table.  This function creates one when necessary.
 */
#define RHASH_TBL(h)                rb_hash_tbl(h, __FILE__, __LINE__)

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 *
 * @internal
 *
 * Declaration of rb_hash_ifnone() is at include/ruby/backward.h.
 */
#define RHASH_IFNONE(h)             rb_hash_ifnone(h)

/**
 * Queries the size of  the hash.  Size here means the number  of keys that the
 * hash stores.
 *
 * @param[in]  h  An instance of RHash.
 * @pre        `h` must be of ::RUBY_T_HASH.
 * @return     The size of the hash.
 */
#define RHASH_SIZE(h)               rb_hash_size_num(h)

/**
 * Checks if the hash is empty.
 *
 * @param[in]  h      An instance of RHash.
 * @pre        `h` must be of ::RUBY_T_HASH.
 * @retval     true   It is.
 * @retval     false  It isn't.
 */
#define RHASH_EMPTY_P(h)            (RHASH_SIZE(h) == 0)

/**
 * Destructively updates the default value of the hash.
 *
 * @param[out]  h       An instance of RHash.
 * @param[in]   ifnone  Arbitrary default value.
 * @pre        `h` must be of ::RUBY_T_HASH.
 *
 * @internal
 *
 * But why you can set this, given rb_hash_ifnone() doesn't exist?
 */
#define RHASH_SET_IFNONE(h, ifnone) rb_hash_set_ifnone((VALUE)h, ifnone)

struct st_table;  /* in ruby/st.h */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * This is  the implementation detail  of #RHASH_SIZE.  People don't  call this
 * directly.
 *
 * @param[in]  hash  An instance of RHash.
 * @pre        `hash` must be of ::RUBY_T_HASH.
 * @return     The size of the hash.
 */
size_t rb_hash_size_num(VALUE hash);

/**
 * This is  the implementation  detail of #RHASH_TBL.   People don't  call this
 * directly.
 *
 * @param[in]  hash  An instance of RHash.
 * @param[in]  file  The `__FILE__`.
 * @param[in]  line  The `__LINE__`.
 * @pre        `hash` must be of ::RUBY_T_HASH.
 * @return     Table that has the contents of the hash.
 */
struct st_table *rb_hash_tbl(VALUE hash, const char *file, int line);

/**
 * This is the  implementation detail of #RHASH_SET_IFNONE.   People don't call
 * this directly.
 *
 * @param[out]  hash    An instance of RHash.
 * @param[in]   ifnone  Arbitrary default value.
 * @pre        `hash` must be of ::RUBY_T_HASH.
 */
VALUE rb_hash_set_ifnone(VALUE hash, VALUE ifnone);
RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_RHASH_H */
