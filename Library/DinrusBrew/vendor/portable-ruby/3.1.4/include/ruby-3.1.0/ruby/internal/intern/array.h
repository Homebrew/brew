#ifndef RBIMPL_INTERN_ARRAY_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_ARRAY_H
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
 * @brief      Public APIs related to ::rb_cArray.
 */
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/noexcept.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* array.c */

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_NOALIAS()
/**
 * Fills the memory region with a series of ::RUBY_Qnil.
 *
 * @param[out]  buf  Buffer to squash.
 * @param[in]   len  Number of objects of `buf`.
 * @post        `buf` is filled with ::RUBY_Qnil.
 */
void rb_mem_clear(VALUE *buf, long len)
    RBIMPL_ATTR_NOEXCEPT(true)
    ;

/**
 * Identical  to  rb_ary_new_from_values(),  except   it  expects  exactly  two
 * parameters.
 *
 * @param[in]  car  Arbitrary ruby object.
 * @param[in]  cdr  Arbitrary ruby object.
 * @return     An  allocated new  array, of  length 2,  whose contents  are the
 *             passed objects.
 */
VALUE rb_assoc_new(VALUE car, VALUE cdr);

/**
 * Try  converting an  object to  its array  representation using  its `to_ary`
 * method, if any.  If there is no such thing, returns ::RUBY_Qnil.
 *
 * @param[in]  obj            Arbitrary ruby object to convert.
 * @exception  rb_eTypeError  `obj.to_ary` returned something non-Array.
 * @retval     RUBY_Qnil      No conversion from `obj` to array defined.
 * @retval     otherwise      Converted array representation of `obj`.
 * @see        rb_io_check_io
 * @see        rb_check_string_type
 * @see        rb_check_hash_type
 */
VALUE rb_check_array_type(VALUE obj);

/**
 * Allocates a new, empty array.
 *
 * @return  An allocated new array, whose length is 0.
 */
VALUE rb_ary_new(void);

/**
 * Identical to rb_ary_new(),  except it additionally specifies  how many rooms
 * of  objects it  should allocate.   This way  you can  create an  array whose
 * capacity is  bigger than the  length of  it.  If you  can say that  an array
 * grows to a  specific amount, this could be effective  than resizing an array
 * over and over again and again.
 *
 * @param[in]  capa  Designed capacity of the generating array.
 * @return     An empty array, whose capacity is `capa`.
 */
VALUE rb_ary_new_capa(long capa);

/**
 * Constructs an array from the passed objects.
 *
 * @param[in]  n    Number of passed objects.
 * @param[in]  ...  Arbitrary ruby objects, filled into the returning array.
 * @return     An array of size `n`, whose contents are the passed objects.
 */
VALUE rb_ary_new_from_args(long n, ...);

/**
 * Identical to rb_ary_new_from_args(), except how objects are passed.
 *
 * @param[in]  n     Number of objects of `elts`.
 * @param[in]  elts  Arbitrary ruby objects, filled into the returning array.
 * @return     An array of size `n`, whose contents are the passed objects.
 */
VALUE rb_ary_new_from_values(long n, const VALUE *elts);

/**
 * Allocates a  "temporary" array.   This is  a hidden  empty array.   Handy on
 * occasions.
 *
 * @param[in]  capa  Designed capacity of the array.
 * @return     A hidden, empty array.
 * @see        rb_obj_hide()
 */
VALUE rb_ary_tmp_new(long capa);

/**
 * Destroys the given array for no reason.
 *
 * @warning  DO NOT USE IT.
 * @warning  Leave this task to our GC.
 * @warning  It was a wrong indea at the first place to let you know about it.
 *
 * @param[out]  ary  The array to be executed.
 * @post        The given array no longer exists.
 * @note        Maybe `Array#clear` could be what you want.
 *
 * @internal
 *
 * Should have moved this to `internal/array.h`.
 */
void rb_ary_free(VALUE ary);

/**
 * Declares that the array is about to  be modified.  This for instance let the
 * array have a dedicated backend storage.
 *
 * @param[out]  ary               Array about to be modified.
 * @exception   rb_eFrozenError   `ary` is frozen.
 * @post        Upon  successful return  the  passed array  is  eligible to  be
 *              modified.
 */
void rb_ary_modify(VALUE ary);

/** @alias{rb_obj_freeze} */
VALUE rb_ary_freeze(VALUE obj);

RBIMPL_ATTR_PURE()
/**
 * Queries if the passed two arrays share the same backend storage.  A use-case
 * for  knowing  such  property is  to  take  a  snapshot  of an  array  (using
 * e.g. rb_ary_replace()), then  check later if that snapshot  still shares the
 * storage with  the original.  Taking  a snapshot is ultra-cheap.   If nothing
 * happens the impact shall be minimal.   But if someone modifies the original,
 * that entity shall pay the cost  of copy-on-write.  You can detect that using
 * this API.
 *
 * @param[in]  lhs          Comparison LHS.
 * @param[in]  rhs          Comparison RHS.
 * @retval     RUBY_Qtrue   They share the same backend storage.
 * @retval     RUBY_Qfalse  They are distinct.
 * @pre        Both arguments must be of ::RUBY_T_ARRAY.
 */
VALUE rb_ary_shared_with_p(VALUE lhs, VALUE rhs);

/**
 * Queries element(s) of  an array.  This is  complicated!  Refer `Array#slice`
 * document for the complete description of how it behaves.
 *
 * @param[in]  argc            Number of objects of `argv`.
 * @param[in]  argv            Up to 2 objects.
 * @param[in]  ary             Target array.
 * @exception  rb_eTypeError   `argv` (or its part) includes non-Integer.
 * @exception  rb_eRangeError  rb_cArithSeq is passed, and is OOB.
 * @return     An  element  (if  requested),  or   an  array  of  elements  (if
 *             requested), or ::RUBY_Qnil (if index OOB).
 *
 * @internal
 *
 * ```rbs
 * # "int" is ::Integer or `#to_int`, defined in builtin.rbs
 *
 * class ::Array[unchecked out T]
 *   def slice
 *     : (int i)                 -> T?
 *     | (int beg, int len)      -> ::Array[T]?
 *     | (Range[int] r)          -> ::Array[T]?
 *     | (ArithmeticSequence as) -> ::Array[T]? # This also raises RagneError.
 * end
 * ```
 */
VALUE rb_ary_aref(int argc, const VALUE *argv, VALUE ary);

/**
 * Obtains a part of the passed array.
 *
 * @param[in]  ary        Target array.
 * @param[in]  beg        Subpart index.
 * @param[in]  len        Requested length of returning array.
 * @retval     RUBY_Qnil  Requested range out of bounds of `ary`.
 * @retval     otherwise  An  allocated new  array whose  contents are  `ary`'s
 *                        `beg` to `len`.
 * @note       Return  array  can  be  shorter than  `len`  when  for  instance
 *             `[0, 1, 2, 3]`'s 4th to 1,000,000,000th is requested.
 */
VALUE rb_ary_subseq(VALUE ary, long beg, long len);

/**
 * Destructively stores  the passed value  to the passed array's  passed index.
 * It also resizes  the array's backend storage so that  the requested index is
 * not out of bounds.
 *
 * @param[out]  ary              Target array to modify.
 * @param[in]   key              Where to store `val`.
 * @param[in]   val              What to store at `key`.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @exception   rb_eIndexError   `key` is negative.
 * @post        `ary`'s `key`th position is occupied with `val`.
 * @post        Depending on `key` and previous  length of `ary` this operation
 *              can  also create  a series  of "hole"  positions inside  of the
 *              backend storage.  They are filled with ::RUBY_Qnil.
 */
void rb_ary_store(VALUE ary, long key, VALUE val);

/**
 * Duplicates an array.
 *
 * @param[in]  ary  Target to duplicate.
 * @return     An allocated new array whose contents are identical to `ary`.
 *
 * @internal
 *
 * Not sure why this has to be something different from `ary_make_shared_copy`,
 * which seems much efficient.
 */
VALUE rb_ary_dup(VALUE ary);

/**
 * I guess there  is no use case  of this function in  extension libraries, but
 * this is a routine identical to rb_ary_dup().  This makes the most sense when
 * the passed array is formerly hidden by rb_obj_hide().
 *
 * @param[in]  ary  An array, possibly hidden.
 * @return     A duplicated new instance of ::rb_cArray.
 */
VALUE rb_ary_resurrect(VALUE ary);

/**
 * Force converts an object to an  array.  It first tries its `#to_ary` method.
 * Takes the result  if any.  Otherwise creates  an array of size  1 whose sole
 * element is the passed object.
 *
 * @param[in]  obj  Arbitrary ruby object.
 * @return     An array representation of `obj`.
 * @note       Unlike    rb_str_to_str()     which    is    a     variant    of
 *             rb_check_string_type(),  rb_ary_to_ary()  is  not a  variant  of
 *             rb_check_array_type().
 */
VALUE rb_ary_to_ary(VALUE obj);

/**
 * Converts an array into a  human-readable string.  Historically its behaviour
 * changed over time.   Currently it is identical to  calling `inspect` method.
 * This behaviour is from that of python (!!) circa 2006.
 *
 * @param[in]  ary  Array to inspect.
 * @return     Recursively inspected representation of `ary`.
 * @see        `[ruby-dev:29520]`
 */
VALUE rb_ary_to_s(VALUE ary);

/**
 * Destructively appends multiple elements at the end of the array.
 *
 * @param[out]  ary              Where to push `train`.
 * @param[in]   train            Arbitrary ruby objects to push to `ary`.
 * @param[in]   len              Number of objects of `train`.
 * @exception   rb_eIndexError   `len` too large.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @return      The passed `ary`.
 * @post        `ary` has contents from `train` appended at its end.
 */
VALUE rb_ary_cat(VALUE ary, const VALUE *train, long len);

/**
 * Special case of rb_ary_cat() that it adds only one element.
 *
 * @param[out]  ary              Where to push `elem`.
 * @param[in]   elem             Arbitrary ruby object to push.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @return      The passed `ary`.
 * @post        `ary` has `elem` appended at its end.
 */
VALUE rb_ary_push(VALUE ary, VALUE elem);

/**
 * Destructively  deletes an  element  from the  end of  the  passed array  and
 * returns what was deleted.
 *
 * @param[out]  ary              Target array to modify.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @return      What  was at  the  end of  `ary`, or  ::RUBY_Qnil  if there  is
 *              nothing to remove.
 * @post        `ary`'s last element, if any, is removed.
 * @note        There is no  way to distinguish whether `ary`  was an 1-element
 *              array whose content was ::RUBY_Qnil, or was empty.
 */
VALUE rb_ary_pop(VALUE ary);

/**
 * Destructively deletes an element from the  beginning of the passed array and
 * returns what  was deleted.  It  can also be seen  as a routine  identical to
 * rb_ary_pop(), except which side of the array to scrub.
 *
 * @param[out]  ary              Target array to modify.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @return      What was at the beginning of  `ary`, or ::RUBY_Qnil if there is
 *              nothing to remove.
 * @post        `ary`'s first element, if any, is removed.  As the name implies
 *              everything else  remaining in `ary` gets  moved towards `ary`'s
 *              beginning.
 * @note        There is no  way to distinguish whether `ary`  was an 1-element
 *              array whose content was ::RUBY_Qnil, or was empty.
 */
VALUE rb_ary_shift(VALUE ary);

/**
 * Destructively prepends the passed item at the beginning of the passed array.
 * It can  also be seen as  a routine identical to  rb_ary_push(), except which
 * side of the array to modify.
 *
 * @param[out]  ary              Target array to modify.
 * @param[in]   elem             Arbitrary ruby object to unshift.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @return      The passed `ary`.
 * @post        `ary` has `elem` prepended at this beginning.
 */
VALUE rb_ary_unshift(VALUE ary, VALUE elem);

RBIMPL_ATTR_PURE()
/**
 * Queries an  element of an array.   When passed offset is  negative it counts
 * backwards.
 *
 * @param[in]  ary  An array to look into.
 * @param[in]  off  Offset (can be negative).
 * @return     ::RUBY_Qnil when  `off` is  out of  bounds of  `ary`.  Otherwise
 *             what is stored at `off`-th position of `ary`.
 * @note       `ary`'s `off`-th element can happen to be ::RUBY_Qnil.
 */
VALUE rb_ary_entry(VALUE ary, long off);

/**
 * Iteratively yields each element of the passed array to the implicitly passed
 * block if any.  In case there is  no block given, an enumerator that does the
 * thing is generated instead.
 *
 * @param[in]  ary  Array to iterate over.
 * @retval     ary  Passed block was evaluated.
 * @retval     otherwise  An instance of ::rb_cEnumerator for `Array#each`.
 */
VALUE rb_ary_each(VALUE ary);

/**
 * Recursively  stringises the  elements  of the  passed  array, flattens  that
 * result, then joins the sequence using the passed separator.
 *
 * @param[in]  ary                 Target array to convert.
 * @param[in]  sep                 Separator.  Either a  string, or ::RUBY_Qnil
 *                                 if you want no separator.
 * @exception  rb_eArgError        Infinite recursion in `ary`.
 * @exception  rb_eTypeError      `sep` is not a string.
 * @exception  rb_eEncCompatError  Strings do not agree with their encodings.
 * @return     An  instance  of   ::rb_cString  which  concatenates  stringised
 *             contents of `ary`, using `sep` as separator.
 */
VALUE rb_ary_join(VALUE ary, VALUE sep);

/**
 * _Destructively_ reverses the passed array in-place.
 *
 * @warning     This is `Array#reverse!`, not `Array#reverse`.
 * @param[out]  ary              Target array to modify.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @return      Passed `ary`.
 * @post        `ary` is reversed.
 */
VALUE rb_ary_reverse(VALUE ary);

/**
 * _Destructively_ rotates the  passed array in-place to towards  its end.  The
 * amount can be negative.  Would rotate to the opposite direction then.
 *
 * @warning     This is `Array#rotate!`, not `Array#rotate`.
 * @param[out]  ary              Target array to modify.
 * @param[in]   rot              Amount of rotation.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @retval      RUBY_Qnil        Not rotated.
 * @retval      ary              Rotated.
 * @post        `ary` is rotated.
 */
VALUE rb_ary_rotate(VALUE ary, long rot);

/**
 * Creates a copy  of the passed array, whose elements  are sorted according to
 * their `<=>` result.
 *
 * @param[in]  ary               Array to sort.
 * @exception  rb_eArgError      Comparison not defined among elements.
 * @exception  rb_eRuntimeError  Infinite recursion in `<=>`.
 * @return     A copy of `ary`, sorted.
 * @note       As of writing  this function uses `qsort`  as backend algorithm,
 *             which means the result is unstable (in terms of sort stability).
 */
VALUE rb_ary_sort(VALUE ary);

/**
 * Destructively sorts the  passed array in-place, according  to each elements'
 * `<=>` result.
 *
 * @param[in]  ary               Target array to modify.
 * @exception  rb_eArgError      Comparison not defined among elements.
 * @exception  rb_eRuntimeError  Infinite recursion in `<=>`.
 * @return     Passed `ary`.
 * @post       `ary` is sorted.
 * @note       As of writing  this function uses `qsort`  as backend algorithm,
 *             which means the result is unstable (in terms of sort stability).
 */
VALUE rb_ary_sort_bang(VALUE ary);

/**
 * Destructively removes elements from the passed array, so that there would be
 * no elements  inside that satisfy  `==` relationship with the  passed object.
 * Returns the last deleted  element if any.  But in case  there was nothing to
 * delete it gets complicated.  It checks  for the implicitly passed block.  If
 * there is  a block  the return value  would be what  the block  evaluates to.
 * Otherwise it resorts to ::RUBY_Qnil.
 *
 * @param[out]  ary              Target array to modify.
 * @param[in]   elem             Template object to match against each element.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @return      What  was  deleted,   or  what  was  the   block  returned,  or
 *              ::RUBY_Qnil (see above).
 * @post        All elements that have `==` relationship with `elem` are purged
 *              from `ary`.  Elements shift their  positions so that `ary` gets
 *              compact.
 *
 * @internal
 *
 * Internally there also is `rb_ary_delete_same`, which compares by identity.
 */
VALUE rb_ary_delete(VALUE ary, VALUE elem);

/**
 * Destructively removes an element which resides  at the specific index of the
 * passed array.  Unlike  rb_ary_stre() the index can be  negative, which means
 * the index counts backwards from the array's tail.
 *
 * @param[out]  ary  Target array to modify.
 * @param[in]   pos  Position (can be negative).
 * @exception   rb_eFrozenError `ary` is frozen.
 * @return      What was deleted, or ::RUBY_Qnil in case of OOB.
 * @post        `ary`'s `pos`-th element is deleted if any.
 * @note        There is no  way to distinguish whether `pos` is  out of bound,
 *              or `pos` did exist but stored ::RUBY_Qnil as an ordinal value.
 */
VALUE rb_ary_delete_at(VALUE ary, long pos);

/**
 * Destructively removes everything form an array.
 *
 * @param[out]  ary              Target array to modify.
 * @exception   rb_eFrozenError  `ary` is frozen.
 * @return      The passed `ary`.
 * @post        `ary` is an empty array.
 */
VALUE rb_ary_clear(VALUE ary);

/**
 * Creates a new array, concatenating the former to the latter.
 *
 * @param[in]  lhs             Source array #1.
 * @param[in]  rhs             Source array #2.
 * @exception  rb_eIndexError  Result array too big.
 * @return     A new array containing `rhs` concatenated to `lhs`.
 * @note       This  operation  doesn't commute.   Don't  get  confused by  the
 *             "plus"  terminology.   For  historical reasons  there  are  some
 *             noncommutative `+`s in Ruby.  This is one of such things.  There
 *             has been a long discussion around `+`s in programming languages.
 *
 * @internal
 *
 * rb_ary_concat() is not  a destructive version of  rb_ary_plus().  They raise
 * different exceptions.  Don't know why though.
 */
VALUE rb_ary_plus(VALUE lhs, VALUE rhs);

/**
 * Destructively appends the contents of latter into the end of former.
 *
 * @param[out]  lhs              Destination array.
 * @param[in]   rhs              Source array.
 * @exception   rb_eFrozenError  `lhs` is frozen.
 * @exception   rb_eIndexError   Result array too big.
 * @exception   rb_eTypeError    `rhs` doesn't respond to `#to_ary`.
 * @return      The passed `lhs`.
 * @post        `lhs` has contents of `rhs` appended to its end.
 */
VALUE rb_ary_concat(VALUE lhs, VALUE rhs);

/**
 * Looks up the passed key, assuming the  passed array is an alist.  An "alist"
 * here  is a  list of  "association"s,  much like  that of  Emacs.  Emacs  has
 * `assoc` function that behaves exactly the same as this one.
 *
 * ```ruby
 * # This is an example of aliist.
 * auto_mode_alist = [
 *   [ /\.[ch]\z/, :"c-mode" ],
 *   [ /\.[ch]pp\z/, :"c++-mode" ],
 *   [ /\.awk\z/, :"awk-mode" ],
 *   [ /\.cs\z/, :"csharp-mode" ],
 *   [ /\.go\z/, :"go-mode" ],
 *   [ /\.java\z/, :"java-mode" ],
 *   [ /\.pas\z/, :"pascal-mode" ],
 *   [ /\.rs\z/, :"rust-mode" ],
 *   [ /\.txt\z/, :"text-mode" ],
 * ]
 * ```
 *
 * This function scans the passed array looking for an element, which itself is
 * an array,  whose first  element is the  passed key.  If  no such  element is
 * found, returns ::RUBY_Qnil.
 *
 * Although this  function expects the passed  array be an array  of arrays, it
 * can happily accept non-array elements; it just ignores such things.
 *
 * @param[in]  alist      An array of arrays.
 * @param[in]  key        Needle.
 * @retval     RUBY_Qnil  Nothing was found.
 * @retval     otherwise  An element in `alist` whose  first element is in `==`
 *                        relationship with `key`.
 */
VALUE rb_ary_assoc(VALUE alist, VALUE key);

/**
 * Identical  to rb_ary_assoc(),  except it  scans  the passed  array from  the
 * opposite direction.
 *
 * @param[in]  alist      An array of arrays.
 * @param[in]  key        Needle.
 * @retval     RUBY_Qnil  Nothing was found.
 * @retval     otherwise  An element in `alist` whose  first element is in `==`
 *                        relationship with `key`.
 */
VALUE rb_ary_rassoc(VALUE alist, VALUE key);

/**
 * Queries if the passed array has the passed entry.
 *
 * @param[in]  ary          Target array to scan.
 * @param[in]  elem         Target array to find.
 * @retval     RUBY_Qfalse  No element  in `ary`  is in `==`  relationship with
 *                          `elem`.
 * @retval     RUBY_Qtrue   There is at least one  element in `ary` which is in
 *                          `==` relationship with `elem`.
 *
 * @internal
 *
 * This is  the only function  in the  entire C API  that is named  using third
 * person singular  form of  a verb  (except #ISASCII etc.,  which are  not our
 * naming).  The counterpart Ruby API of this function is `Array#include?`.
 */
VALUE rb_ary_includes(VALUE ary, VALUE elem);

/**
 * Recursively compares each elements of the two arrays one-by-one using `<=>`.
 *
 * @param[in]  lhs        Comparison LHS.
 * @param[in]  rhs        Comparison RHS.
 * @retval     RUBY_Qnil  `lhs` and `rhs` are not comparable.
 * @retval     -1         `lhs` is less than `rhs`.
 * @retval      0         They are equal.
 * @retval      1         `rhs` is less then `lhs`.
 */
VALUE rb_ary_cmp(VALUE lhs, VALUE rhs);

/**
 * Replaces the contents of the former object with the contents of the latter.
 *
 * @param[out]  copy               Destination object.
 * @param[in]   orig               Source object.
 * @exception   rb_eTypeError     `orig` has no implicit conversion to Array.
 * @exception   rb_eFrozenError   `copy` is frozen.
 * @return      The passed `copy`.
 * @post        `copy`'s  former  components are  abandoned.   It  now has  the
 *              identical length and contents to `orig`.
 */
VALUE rb_ary_replace(VALUE copy, VALUE orig);

/**
 * This _was_  a generalisation  of `Array#values_at`,  `Struct#values_at`, and
 * `MatchData#values_at`.  It begun its life  as a refactoring effort.  However
 * as Ruby  evolves over  time, as  of writing  none of  aforementioned methods
 * share their implementations at all.   This function is not deprecated; still
 * works as it has been.  But it is now kind of like a rudimentum.
 *
 * This  function  takes an  object,  which  is a  receiver,  and  a series  of
 * "indices",  which are  either integers,  or ranges  of integers.   Calls the
 * passed callback  for each of those  indices, along with the  receiver.  This
 * callback is  expected to do something  like rb_ary_aref(), rb_struct_aref(),
 * etc.   In  case of  a  range  index  rb_range_beg_len() expands  the  range.
 * Finally  return values  of  the  callback are  gathered  as  an array,  then
 * returned.
 *
 * @param[in]  obj   Arbitrary ruby object.
 * @param[in]  olen  "Length" of `obj`.
 * @param[in]  argc  Number of objects of `argv`.
 * @param[in]  argv  List of "indices", described above.
 * @param[in]  func  Callback function.
 * @return     A new instance of ::rb_cArray gathering `func`outputs.
 *
 * @internal
 *
 * `Array#values_at` no  longer uses this  function.  There is no  reason apart
 * from historical ones to list this function here.
 */
VALUE rb_get_values_at(VALUE obj, long olen, int argc, const VALUE *argv, VALUE (*func)(VALUE obj, long oidx));

/**
 * Expands or shrinks the passed array to the passed length.
 *
 * @param[out]  ary              An array to modify.
 * @param[in]   len              Desired length of `ary`.
 * @exception   rb_eFrozenError  `ary`  is frozen.
 * @exception   rb_eIndexError   `len` too long.
 * @return      The passed `ary`.
 * @post        `ary`'s length is `len`.
 * @post        Depending on `len` and previous  length of `ary` this operation
 *              can  also create  a series  of "hole"  positions inside  of the
 *              backend storage.  They are filled with ::RUBY_Qnil.
 *
 * @internal
 *
 * `len` is signed.  Intentional or...?
 */
VALUE rb_ary_resize(VALUE ary, long len);

#define rb_ary_new2 rb_ary_new_capa         /**< @old{rb_ary_new_capa} */
#define rb_ary_new3 rb_ary_new_from_args    /**< @old{rb_ary_new_from_args} */
#define rb_ary_new4 rb_ary_new_from_values  /**< @old{rb_ary_new_from_values} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_ARRAY_H */
