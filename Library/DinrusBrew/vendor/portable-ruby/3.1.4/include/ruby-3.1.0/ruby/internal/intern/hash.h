#ifndef RBIMPL_INTERN_HASH_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_HASH_H
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
 * @brief      Public APIs related to ::rb_cHash.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/st.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* hash.c */

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_st_foreach(), except it  raises exceptions when the callback
 * function tampers the table during iterating over it.
 *
 * @param[in]  st                Table to iterate over.
 * @param[in]  func              Callback function to apply.
 * @param[in]  arg               Passed as-is to `func`.
 * @exception  rb_eRuntimeError  `st` was tampered during iterating.
 *
 * @internal
 *
 * This is declared here because exceptions are Ruby level concept.
 *
 * This is in fact a very thin wrapper of rb_st_foreach_check().
 */
void rb_st_foreach_safe(struct st_table *st, st_foreach_callback_func *func, st_data_t arg);

/** @alias{rb_st_foreach_safe} */
#define st_foreach_safe rb_st_foreach_safe

/**
 * Try  converting an  object to  its hash  representation using  its `to_hash`
 * method, if any.  If there is no such thing, returns ::RUBY_Qnil.
 *
 * @param[in]  obj            Arbitrary ruby object to convert.
 * @exception  rb_eTypeError  `obj.to_hash` returned something non-Hash.
 * @retval     RUBY_Qnil      No conversion from `obj` to hash defined.
 * @retval     otherwise      Converted hash representation of `obj`.
 * @see        rb_io_check_io
 * @see        rb_check_array_type
 * @see        rb_check_string_type
 *
 * @internal
 *
 * There   is  no   rb_hash_to_hash()   that   analogous  to   rb_str_to_str().
 * Intentional or ...?
 */
VALUE rb_check_hash_type(VALUE obj);

RBIMPL_ATTR_NONNULL(())
/**
 * Iterates   over  a   hash.   This   basically   does  the   same  thing   as
 * rb_st_foreach().  But because the passed hash is a Ruby object, its keys and
 * values are both Ruby objects.
 *
 * @param[in]  hash              An instance of ::rb_cHash to iterate over.
 * @param[in]  func              Callback function to yield.
 * @param[in]  arg               Passed as-is to `func`.
 * @exception  rb_eRuntimeError  `hash` was tampered during iterating.
 */
void rb_hash_foreach(VALUE hash, int (*func)(VALUE key, VALUE val, VALUE arg), VALUE arg);

/**
 * Calculates a message  authentication code of the passed  object.  The return
 * value is  a very small  integer used as  an index of a  key of a  table.  In
 * order  to calculate  the value  this function  calls `#hash`  method of  the
 * passed  object.  Ruby  provides you  a default  implementation.  But  if you
 * implement  your class  in C,  that  default implementation  cannot know  the
 * underlying data structure.  You must implement your own `#hash` method then,
 * which  must return  an integer  of  uniform distribution  in a  sufficiently
 * instant manner.
 *
 * @param[in]  obj            Arbitrary Ruby object.
 * @exception  rb_eTypeError  `obj.hash` returned something non-Integer.
 * @return     A small integer.
 * @note       `#hash` can return very big integers, but they get truncated.
 */
VALUE rb_hash(VALUE obj);

/**
 * Creates a new, empty hash object.
 *
 * @return  An allocated new instance of ::rb_cHash.
 */
VALUE rb_hash_new(void);

/**
 * Duplicates a hash.
 *
 * @param[in]  hash  An instance of ::rb_cHash.
 * @return     An  allocated new  instance  of ::rb_cHash,  whose contents  are
 *             a verbatim copy of from `hash`.
 */
VALUE rb_hash_dup(VALUE hash);

/** @alias{rb_obj_freeze} */
VALUE rb_hash_freeze(VALUE obj);

/**
 * Queries the given key  in the given hash table.  If there is  the key in the
 * hash, returns the  value associated with the key.  Otherwise  it returns the
 * "default" value (defined per hash table).
 *
 * @param[in]  hash  Hash table to look into.
 * @param[in]  key   Hash key to look for.
 * @return     Either the value associated with the  key, or the default one if
 *             absent.
 */
VALUE rb_hash_aref(VALUE hash, VALUE key);

/**
 * Identical  to  rb_hash_aref(),  except  it always  returns  ::RUBY_Qnil  for
 * misshits.
 *
 * @param[in]  hash  Hash table to look into.
 * @param[in]  key   Hash key to look for.
 * @return     Either  the value  associated with  the key,  or ::RUBY_Qnil  if
 *             absent.
 * @note       A hash can  store ::RUBY_Qnil as an ordinary  value.  You cannot
 *             distinguish whether the  key is missing, or  just its associated
 *             value happens to be ::RUBY_Qnil, as far as you use this API.
 */
VALUE rb_hash_lookup(VALUE hash, VALUE key);

/**
 * Identical  to rb_hash_lookup(),  except you  can specify  what to  return on
 * misshits.  This is much like 2-arguments version of `Hash#fetch`.
 *
 * ```CXX
 * VALUE hash;
 * VALUE key;
 * VALUE tmp = rb_obj_alloc(rb_cObject);
 * VALUE val = rb_hash_lookup2(hash, key, tmp);
 * if (val == tmp) {
 *     printf("misshit");
 * }
 * else {
 *     printf("hit");
 * }
 * ```
 *
 * @param[in]  hash       Hash table to look into.
 * @param[in]  key        Hash key to look for.
 * @param[in]  def        Default value.
 * @retval     def        `hash` does not have `key`.
 * @retval     otherwise  The value associated with `key`.
 */
VALUE rb_hash_lookup2(VALUE hash, VALUE key, VALUE def);

/**
 * Identical  to rb_hash_lookup(),  except  it yields  the (implicitly)  passed
 * block instead of returning ::RUBY_Qnil.
 *
 * @param[in]  hash          Hash table to look into.
 * @param[in]  key           Hash key to look for.
 * @exception  rb_eKeyError  No block given.
 * @return     Either  the value  associated with  the key,  or what  the block
 *             evaluates to if absent.
 */
VALUE rb_hash_fetch(VALUE hash, VALUE key);

/**
 * Inserts or replaces ("upsert"s) the objects into the given hash table.  This
 * basically associates the  given value with the given key.   On duplicate key
 * this function updates its associated value with the given one.  Otherwise it
 * inserts the association at the end of the table.
 *
 * @param[out]  hash             Target hash table to modify.
 * @param[in]   key              Arbitrary Ruby object.
 * @param[in]   val              A value to be associated with `key`.
 * @exception   rb_eFrozenError  `hash` is frozen.
 * @return      The passed `val`
 * @post        `val` is associated with `key` in `hash`.
 */
VALUE rb_hash_aset(VALUE hash, VALUE key, VALUE val);

/**
 * Swipes everything out of the passed hash table.
 *
 * @param[out]  hash             Target to clear.
 * @exception   rb_eFrozenError  `hash`is frozen.
 * @return      The passed `hash`
 * @post        `hash` has no contents.
 */
VALUE rb_hash_clear(VALUE hash);

/**
 * Deletes each entry for which the block  returns a truthy value.  If there is
 * no block given, it returns an enumerator that does the thing.
 *
 * @param[out]  hash             Target hash to modify.
 * @exception   rb_eFrozenError  `hash` is frozen.
 * @retval      hash             The hash is modified.
 * @retval      otherwise        An instance of ::rb_cEnumerator that does it.
 */
VALUE rb_hash_delete_if(VALUE hash);

/**
 * Deletes the passed key from the passed hash table, if any.
 *
 * @param[out]  hash       Target hash to modify.
 * @param[in]   key        Key to delete.
 * @retval      RUBY_Qnil  `hash` has no such key as `key`.
 * @retval      otherwise  What was associated with `key`.
 * @post        `hash` has no such key as `key`.
 */
VALUE rb_hash_delete(VALUE hash, VALUE key);

/**
 * Inserts  a list  of  key-value pairs  into  a  hash table  at  once.  It  is
 * semantically  identical to  repeatedly  calling rb_hash_aset(),  but can  be
 * faster than that.
 *
 * @param[in]   argc  Length of `argv`, must be even.
 * @param[in]   argv  A list of key, value, key, value, ...
 * @param[out]  hash  Target hash table to modify.
 * @post        `hash` has contents from `argv`.
 * @note        `argv` is allowed to be NULL as long as `argc` is zero.
 *
 * @internal
 *
 * What happens for  duplicated keys?  Well it silently discards  older ones to
 * accept the newest (rightmost) one.  This behaviour also mimics repeated call
 * of rb_hash_aset().
 */
void rb_hash_bulk_insert(long argc, const VALUE *argv, VALUE hash);

/**
 * Type of callback functions to pass to rb_hash_update_by().
 *
 * @param[in]  newkey  A key of the table.
 * @param[in]  oldkey  Value associated with `key` in hash1.
 * @param[in]  value   Value associated with `key` in hash2.
 * @return     Either one of the passed values to take.
 */
typedef VALUE rb_hash_update_func(VALUE newkey, VALUE oldkey, VALUE value);

/**
 * Destructively merges two hash tables into one.  It resolves key conflicts by
 * calling the passed function and take its return value.
 *
 * @param[out]  hash1             Target hash to be modified.
 * @param[in]   hash2             A hash to merge into `hash1`.
 * @param[in]   func              Conflict reconciler.
 * @exception   rb_eFrozenError   `hash1` is frozen.
 * @exception   rb_eRuntimeError  `hash2` is updated instead.
 * @return      The passed `hash1`.
 * @post        Contents of `hash2` is merged into `hash1`.
 * @note        You can  pass zero to  `func`.  This means values  from `hash2`
 *              are always taken.
 */
VALUE rb_hash_update_by(VALUE hash1, VALUE hash2, rb_hash_update_func *func);

/* file.c */

/**
 * This function is mysterious.  What it does is not immediately obvious.  Also
 * what it does seems platform dependent.
 *
 * @param[in]  path       A local path.
 * @retval     0          The "check" succeeded.
 * @retval     otherwise  The "check" failed.
 */
int rb_path_check(const char *path);

/* hash.c */

/**
 * @deprecated  This function  once was a thing  in the old days,  but makes no
 *              sense   any   longer   today.   Exists   here   for   backwards
 *              compatibility only.  You can safely forget about it.
 *
 * @return      0 always.
 */
int rb_env_path_tainted(void);

/**
 * Destructively removes every environment variables of the running process.
 *
 * @return  The `ENV` object.
 * @post    The process has no environment variables.
 */
VALUE rb_env_clear(void);

/**
 * Identical to  #RHASH_SIZE(), except  it returns the  size in  Ruby's integer
 * instead of C's.
 *
 * @param[in]  hash  A hash object.
 * @return     The size of the hash.
 */
VALUE rb_hash_size(VALUE hash);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_HASH_H */
