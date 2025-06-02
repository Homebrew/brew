#ifndef RBIMPL_INTERN_BIGNUM_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_BIGNUM_H
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
 * @brief      Public APIs related to so-called rb_cBignum.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/backward/2/long_long.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* bignum.c */

/**
 * Allocates a bignum object.
 *
 * @param[in]  len   Length of the bignum's backend storage, in words.
 * @param[in]  sign  Sign of the bignum.
 * @return     An allocated new bignum instance.
 * @note       This only allocates an object, doesn't fill its value in.
 *
 * @internal
 *
 * @shyouhei  finds it  hard to  use from  extension libraries.   `len` is  per
 * `BDIGIT` but its definition is hidden.
 */
VALUE rb_big_new(size_t len, int sign);

/**
 * Queries if  the passed bignum  instance is a  "bigzro".  What is  a bigzero?
 * Well, bignums  are for very big  integers, but can also  represent tiny ones
 * like -1,  0, 1.   Bigzero are  instances of bignums  whose values  are zero.
 * Knowing if a bignum is bigzero can  be handy on occasions, like for instance
 * detecting division by zero situation.
 *
 * @param[in]  x  A bignum.
 * @retval     1  It is a bigzero.
 * @retval     0  Otherwise.
 */
int rb_bigzero_p(VALUE x);

/**
 * Duplicates the given bignum.
 *
 * @param[in]  num  A bignum.
 * @return     An allocated bignum, who is equivalent to `num`.
 */
VALUE rb_big_clone(VALUE num);

/**
 * Destructively modify the passed bignum into 2's complement representation.
 *
 * @note  By default bignums are in signed magnitude system.
 *
 * @param[out]  num  A bignum to modify.
 */
void rb_big_2comp(VALUE num);

/**
 * Normalises the passed bignum.  It for  instance returns a fixnum of the same
 * value if fixnum can represent that number.
 *
 * @param[out]  x  Target bignum (can be destructively modified).
 * @return      An integer of the identical value (can be `x` itself).
 */
VALUE rb_big_norm(VALUE x);

/**
 * Destructively resizes the backend storage of the passed bignum.
 *
 * @param[out]  big  A bignum.
 * @param[in]   len  New length of `big`'s backend, in words.
 */
void rb_big_resize(VALUE big, size_t len);

RBIMPL_ATTR_NONNULL(())
/**
 * Parses C's string to convert into a Ruby's integer.  It understands prefixes
 * (e.g. `0x`) and underscores.
 *
 * @param[in]  str           Stringised representation of the return value.
 * @param[in]  base          Base of conversion.   Must be `-36..36` inclusive,
 *                           except `1`.  `2..36` means  the conversion is done
 *                           according to it,  with unmatched prefix understood
 *                           as  a part  of  the result.   `-36..-2` means  the
 *                           conversion  honours prefix  when  present, or  use
 *                           `-base` when  absent. `0` is equivalent  to `-10`.
 *                           `-1` mandates a prefix. `1` is an error.
 * @param[in]  badcheck      Whether  to raise  ::rb_eArgError on  failure.  If
 *                           `0`  is  passed  here  this  function  can  return
 *                           `INT2FIX(0)` for parse errors.
 * @exception  rb_eArgError  Failed to parse (and `badcheck` is truthy).
 * @return     An instance of ::rb_cInteger,  which is a numeric interpretation
 *             of what is written in `str`.
 *
 * @internal
 *
 * Not sure if it intentionally accepts `base  == -1` or is just buggy.  Nobody
 * practically uses negative bases these days.
 */
VALUE rb_cstr_to_inum(const char *str, int base, int badcheck);

/**
 * Identical to rb_cstr2inum(), except it takes Ruby's strings instead of C's.
 *
 * @param[in]  str                 Stringised  representation   of  the  return
 *                                 value.
 * @param[in]  base                Base  of  conversion.    Must  be  `-36..36`
 *                                 inclusive,  except `1`.   `2..36` means  the
 *                                 conversion  is done  according  to it,  with
 *                                 unmatched prefix understood as a part of the
 *                                 result.   `-36..-2`   means  the  conversion
 *                                 honours prefix when  present, or use `-base`
 *                                 when  absent. `0`  is  equivalent to  `-10`.
 *                                 `-1` mandates a prefix. `1` is an error.
 * @param[in]  badcheck            Whether to raise  ::rb_eArgError on failure.
 *                                 If  `0` is  passed  here  this function  can
 *                                 return `INT2FIX(0)` for parse errors.
 * @exception  rb_eArgError        Failed to parse (and `badcheck` is truthy).
 * @exception  rb_eTypeError       `str` is not a string.
 * @exception  rb_eEncCompatError  `str` is not ASCII compatible.
 * @return     An instance of ::rb_cInteger,  which is a numeric interpretation
 *             of what is written in `str`.
 */
VALUE rb_str_to_inum(VALUE str, int base, int badcheck);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_cstr_to_inum(), except the second argument controls the base
 * and badcheck at  once.  It basically doesn't raise for  parse errors, unless
 * the base is zero.
 *
 * This is an older API.  New codes might prefer rb_cstr_to_inum().
 *
 * @param[in]  str           Stringised representation of the return value.
 * @param[in]  base          Base of conversion.   Must be `-36..36` inclusive,
 *                           except `1`.  `2..36` means  the conversion is done
 *                           according to it,  with unmatched prefix understood
 *                           as  a part  of  the result.   `-36..-2` means  the
 *                           conversion  honours prefix  when  present, or  use
 *                           `-base` when  absent. `0` is equivalent  to `-10`.
 *                           `-1` mandates a prefix. `1` is an error.
 * @exception  rb_eArgError  Failed to parse (and `base` is zero).
 * @return     An instance of ::rb_cInteger,  which is a numeric interpretation
 *             of what is written in `str`.
 */
VALUE rb_cstr2inum(const char *str, int base);

/**
 * Identical to rb_str_to_inum(), except the  second argument controls the base
 * and  badcheck at  once.  It  can  also be  seen  as a  routine identical  to
 * rb_cstr2inum(), except it takes Ruby's strings instead of C's.
 *
 * This is an older API.  New codes might prefer rb_cstr_to_inum().
 *
 * @param[in]  str                 Stringised  representation   of  the  return
 *                                 value.
 * @param[in]  base                Base  of  conversion.    Must  be  `-36..36`
 *                                 inclusive,  except `1`.   `2..36` means  the
 *                                 conversion  is done  according  to it,  with
 *                                 unmatched prefix understood as a part of the
 *                                 result.   `-36..-2`   means  the  conversion
 *                                 honours prefix when  present, or use `-base`
 *                                 when  absent. `0`  is  equivalent to  `-10`.
 *                                 `-1` mandates a prefix. `1` is an error.
 * @exception  rb_eArgError        Failed to parse (and `base` is zero).
 * @exception  rb_eTypeError       `str` is not a string.
 * @exception  rb_eEncCompatError  `str` is not ASCII compatible.
 * @return     An instance of ::rb_cInteger,  which is a numeric interpretation
 *             of what is written in `str`.
 */
VALUE rb_str2inum(VALUE str, int base);

/**
 * Generates a place-value representation of the passed integer.
 *
 * @param[in]  x               An integer to stringify.
 * @param[in]  base            `2` to `36` inclusive for each radix.
 * @exception  rb_eArgError    `base` is out of range.
 * @exception  rb_eRangeError  `x` is too big, cannot represent in string.
 * @return     An instance of ::rb_cString which represents `x`.
 */
VALUE rb_big2str(VALUE x, int base);

/**
 * Converts a bignum into C's `long`.
 *
 * @param[in]  x               A bignum.
 * @exception  rb_eRangeError  `x` is out of range of `long`.
 * @return     The passed value converted into C's `long`.
 */
long rb_big2long(VALUE x);

/** @alias{rb_big2long} */
#define rb_big2int(x) rb_big2long(x)

/**
 * Converts a bignum into C's `unsigned long`.
 *
 * @param[in]  x               A bignum.
 * @exception  rb_eRangeError  `x` is out of range of `unsigned long`.
 * @return     The passed value converted into C's `unsigned long`.
 *
 * @internal
 *
 * This function  can generate  a very  large positive  integer for  a negative
 * input.   For instance  applying  Ruby's  -4,611,686,018,427,387,905 to  this
 * function yields C's  13,835,058,055,282,163,711 on my machine.   This is how
 * it has been.  Cannot change any longer.
 */
unsigned long rb_big2ulong(VALUE x);

/** @alias{rb_big2long} */
#define rb_big2uint(x) rb_big2ulong(x)

#if HAVE_LONG_LONG
/**
 * Converts a bignum into C's `long long`.
 *
 * @param[in]  x               A bignum.
 * @exception  rb_eRangeError  `x` is out of range of `long long`.
 * @return     The passed value converted into C's `long long`.
 */
LONG_LONG rb_big2ll(VALUE);

/**
 * Converts a bignum into C's `unsigned long long`.
 *
 * @param[in]  x               A bignum.
 * @exception  rb_eRangeError  `x` is out of range of `unsigned long long`.
 * @return     The passed value converted into C's `unsigned long long`.
 *
 * @internal
 *
 * This function  can generate  a very  large positive  integer for  a negative
 * input.   For instance  applying  Ruby's  -4,611,686,018,427,387,905 to  this
 * function yields C's  13,835,058,055,282,163,711 on my machine.   This is how
 * it has been.  Cannot change any longer.
 */
unsigned LONG_LONG rb_big2ull(VALUE);

#endif  /* HAVE_LONG_LONG */

RBIMPL_ATTR_NONNULL(())
/**
 * Converts a bignum into a series of its parts.
 *
 * @param[in]   val            An integer.
 * @param[out]  buf            Return buffer.
 * @param[in]   num_longs      Number of words of `buf`.
 * @exception   rb_eTypeError  `val` doesn't respond to `#to_int`.
 * @post        `buf` is filled with  `val`'s 2's complement representation, in
 *              the host CPU's  native byte order, from  least significant word
 *              towards the most significant one, for `num_longs` words.
 * @note        The "pack" terminology comes from `Array#pack`.
 */
void rb_big_pack(VALUE val, unsigned long *buf, long num_longs);

RBIMPL_ATTR_NONNULL(())
/**
 * Constructs a (possibly very big) bignum from a series of integers.  `buf[0]`
 * would be the return value's least significant word; `buf[num_longs-1]` would
 * be that of most significant.
 *
 * @param[in]  buf           A series of integers.
 * @param[in]  num_longs     Number of words of `buf`.
 * @exception  rb_eArgError  Result would be too big.
 * @return     An instance  of ::rb_cInteger which  is an "unpack"-ed  value of
 *             the parameters.
 * @note       The "unpack" terminology comes from `String#pack`.
 */
VALUE rb_big_unpack(unsigned long *buf, long num_longs);

/* pack.c */

RBIMPL_ATTR_NONNULL(())
/**
 * Encodes a Unicode codepoint into its UTF-8 representation.
 *
 * @param[out]  buf             Return buffer, must at least be 6 bytes width.
 * @param[in]   uv              An Unicode codepoint.
 * @exception   rb_eRangeError  `uv` is out of Unicode.
 * @return      Number of bytes written to `buf`
 * @post        `buf` holds a UTF-8 representation of `uv`.
 */
int rb_uv_to_utf8(char buf[6], unsigned long uv);

/* bignum.c */

/**
 * Converts a C's `double` into a bignum.
 *
 * @param[in]  d                     A value to convert.
 * @exception  rb_eFloatDomainError  `d` is Inf/NaN.
 * @return     An instance of ::rb_cInteger whose value is approximately `d`.
 *
 * @internal
 *
 * @shyouhei is not sure if the result  is guaranteed to be the nearest integer
 * of `d`.
 */
VALUE rb_dbl2big(double d);

/**
 * Converts a bignum into C's `double`.
 *
 * @param[in]  x  A bignum.
 * @return     The passed value converted into C's `double`.
 *
 * @internal
 *
 * @shyouhei is not sure if the result  is guaranteed to be `x`'s nearest value
 * that a `double` can represent.
 */
double rb_big2dbl(VALUE x);

/**
 * Compares the passed two bignums.
 *
 * @param[in]  lhs  Comparison LHS.
 * @param[in]  rhs  Comparison RHS.
 * @retval     -1   `rhs` is bigger than `lhs`.
 * @retval     0    They are identical.
 * @retval     1    `lhs` is bigger than `rhs`.
 * @see        rb_num_coerce_cmp()
 */
VALUE rb_big_cmp(VALUE lhs, VALUE rhs);

/**
 * Equality, in terms of `==`.  This checks if the _value_ is the same, not the
 * identity.  For instance `1 == 1.0` must hold.
 *
 * @param[in]  lhs          Comparison LHS.
 * @param[in]  rhs          Comparison RHS.
 * @retval     RUBY_Qtrue   They are the same.
 * @retval     RUBY_Qfalse  They are different.
 */
VALUE rb_big_eq(VALUE lhs, VALUE rhs);

/**
 * Equality,  in terms  of  `eql?`.   Unlike rb_big_eq()  it  does not  convert
 * ::rb_cFloat etc.   This function  returns ::RUBY_Qtrue if  and only  if both
 * parameters are bignums, which represent the identical numerical value.
 *
 * @param[in]  lhs          Comparison LHS.
 * @param[in]  rhs          Comparison RHS.
 * @retval     RUBY_Qtrue   They are identical.
 * @retval     RUBY_Qfalse  They are distinct.
 */
VALUE rb_big_eql(VALUE lhs, VALUE rhs);

/**
 * Performs addition of the passed two objects.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x + y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_big_plus(VALUE x, VALUE y);

/**
 * Performs subtraction of the passed two objects.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x - y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_big_minus(VALUE x, VALUE y);

/**
 * Performs multiplication of the passed two objects.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x * y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_big_mul(VALUE x, VALUE y);

/**
 * Performs division of the passed two objects.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x / y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_big_div(VALUE x, VALUE y);

/**
 * Performs "integer division".  This is different from rb_big_div().
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x.div y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_big_idiv(VALUE x, VALUE y);

/**
 * Performs modulo of the passed two objects.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x % y` evaluates to.
 * @see        rb_num_coerce_bin()
 *
 * @internal
 *
 * There also is `rb_big_remainder()` internally,  which is different from this
 * one.
 */
VALUE rb_big_modulo(VALUE x, VALUE y);

/**
 * Performs "divmod" operation.   The operation in bignum's context  is that it
 * calculates rb_big_idiv() and rb_big_modulo() at once.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x.divmod y` evaluates to.
 * @see        rb_num_coerce_bin()
 */
VALUE rb_big_divmod(VALUE x, VALUE y);

/**
 * Raises `x` to the powerof `y`.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x ** y` evaluates to.
 * @see        rb_num_coerce_bin()
 * @note       This can return  an instance of ::rb_cFloat, even  when both `x`
 *             and `y` are bignums.  Or an instance of ::rb_cRational, when for
 *             instance `y` is negative.
 */
VALUE rb_big_pow(VALUE x, VALUE y);

/**
 * Performs bitwise and of the passed two objects.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x & y` evaluates to.
 * @see        rb_num_coerce_bit()
 */
VALUE rb_big_and(VALUE x, VALUE y);

/**
 * Performs bitwise or of the passed two objects.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x | y` evaluates to.
 * @see        rb_num_coerce_bit()
 */
VALUE rb_big_or(VALUE x, VALUE y);

/**
 * Performs exclusive or of the passed two objects.
 *
 * @param[in]  x  A bignum.
 * @param[in]  y  Arbitrary ruby object.
 * @return     What `x ^ y` evaluates to.
 * @see        rb_num_coerce_bit()
 */
VALUE rb_big_xor(VALUE x, VALUE y);

/**
 * Performs shift left.
 *
 * @param[in]  x              A bignum.
 * @param[in]  y              Shift amount.
 * @exception  rb_eTypeError  `y` is not an integer.
 * @exception  rb_eArgError   `y` is too big.
 * @return     `x` shifted left to `y` bits.
 * @note       `y` can be negative.  Shifts right then.
 */
VALUE rb_big_lshift(VALUE x, VALUE y);

/**
 * Performs shift right.
 *
 * @param[in]  x              A bignum.
 * @param[in]  y              Shift amount.
 * @exception  rb_eTypeError  `y` is not an integer.
 * @return     `x` shifted right to `y` bits.
 * @note       This is arithmetic.  Because bignums  are not bitfields there is
 *             no shift right logical operator.
 */
VALUE rb_big_rshift(VALUE x, VALUE y);

/**
 * @name Flags for rb_integer_pack()/rb_integer_unpack()
 * @{
 */

/** Stores/interprets the most significant word as the first word. */
#define INTEGER_PACK_MSWORD_FIRST       0x01

/** Stores/interprets the least significant word as the first word. */
#define INTEGER_PACK_LSWORD_FIRST       0x02

/**
 * Stores/interprets the most  significant byte in a word as  the first byte in
 * the word.
 */
#define INTEGER_PACK_MSBYTE_FIRST       0x10

/**
 * Stores/interprets the least significant byte in  a word as the first byte in
 * the word.
 */
#define INTEGER_PACK_LSBYTE_FIRST       0x20

/**
 * Means   either  #INTEGER_PACK_MSBYTE_FIRST   or  #INTEGER_PACK_LSBYTE_FIRST,
 * depending on the host processor's endian.
 */
#define INTEGER_PACK_NATIVE_BYTE_ORDER  0x40

/** Uses 2's complement representation. */
#define INTEGER_PACK_2COMP              0x80

/** Uses "generic" implementation (handy on test). */
#define INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION     0x400

/**
 * Always generates  a bignum object even  if the integer can  be representable
 * using fixnum scheme (unpack only)
 */
#define INTEGER_PACK_FORCE_BIGNUM       0x100

/**
 * Interprets the  input as  a signed  negative number  (unpack only).   If not
 * specified returns a positive number.
 */
#define INTEGER_PACK_NEGATIVE           0x200

/** Little endian combination. */
#define INTEGER_PACK_LITTLE_ENDIAN \
    (INTEGER_PACK_LSWORD_FIRST | \
     INTEGER_PACK_LSBYTE_FIRST)

/** Big endian combination */
#define INTEGER_PACK_BIG_ENDIAN \
    (INTEGER_PACK_MSWORD_FIRST | \
     INTEGER_PACK_MSBYTE_FIRST)

/** @} */

RBIMPL_ATTR_NONNULL(())
/**
 * Exports an integer into a buffer.   This function fills the buffer specified
 * by `words`  and `numwords` as `val`  in the format specified  by `wordsize`,
 * `nails` and `flags`.
 *
 * @param[in]   val            Integer   or  integer-like   object  which   has
 *                             `#to_int` method.
 * @param[out]  words          Return buffer.
 * @param[in]   numwords       Number of words of `words`.
 * @param[in]   wordsize       Number of bytes per word.
 * @param[in]   nails          Number  of   padding  bits  in  a   word.   Most
 *                             significant nails  bits of each word  are filled
 *                             by zero.
 * @param[in]   flags          Bitwise  or  of   constants  whose  name  starts
 *                             "INTEGER_PACK_".
 * @exception   rb_eTypeError  `val` doesn't respond to `#to_int`.
 *
 * Possible flags are:
 *
 *   - #INTEGER_PACK_MSWORD_FIRST:
 *       Stores the most significant word as the first word.
 *
 *   - #INTEGER_PACK_LSWORD_FIRST:
 *       Stores the least significant word as the first word.
 *
 *   - #INTEGER_PACK_MSBYTE_FIRST:
 *       Stores the most  significant byte in a  word as the first  byte in the
 *       word.
 *
 *   - #INTEGER_PACK_LSBYTE_FIRST:
 *       Stores the least significant  byte in a word as the  first byte in the
 *       word.
 *
 *   - #INTEGER_PACK_NATIVE_BYTE_ORDER:
 *       Either   #INTEGER_PACK_MSBYTE_FIRST    or   #INTEGER_PACK_LSBYTE_FIRST
 *       corresponding to the host's endian.
 *
 *   - #INTEGER_PACK_2COMP:
 *       Uses 2's complement representation.
 *
 *   - #INTEGER_PACK_LITTLE_ENDIAN: Shorthand of
 *       `INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_LSBYTE_FIRST`.
 *
 *   - #INTEGER_PACK_BIG_ENDIAN: Shorthand of
 *       `INTEGER_PACK_MSWORD_FIRST|INTEGER_PACK_MSBYTE_FIRST`.
 *
 *   - #INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION:
 *       Uses generic implementation (for test and debug).
 *
 * This  function  fills  the  buffer  specified  by  `words`  as  `val`'s  2's
 * complement representation  if #INTEGER_PACK_2COMP  is specified  in `flags`.
 * Otherwise it fills `words` as `abs(val)`  and signedness is returned via the
 * return value.
 *
 * @return  The  signedness and  overflow  condition.   The overflow  condition
 *          depends on #INTEGER_PACK_2COMP.
 *
 * When #INTEGER_PACK_2COMP is not specified:
 *
 *   - `-2` :
 *       Negative overflow.  `val <= -2**(numwords*(wordsize*CHAR_BIT-nails))`
 *
 *   - `-1` :
 *       Negative without overflow.
 *       `-2**(numwords*(wordsize*CHAR_BIT-nails)) < val < 0`
 *
 *   - `0` : zero.  `val == 0`
 *
 *   - `1` :
 *       Positive without overflow.
 *       `0 < val < 2**(numwords*(wordsize*CHAR_BIT-nails))`
 *
 *   - `2` :
 *       Positive overflow.  `2**(numwords*(wordsize*CHAR_BIT-nails)) <= val`
 *
 * When #INTEGER_PACK_2COMP is specified:
 *
 *   - `-2` :
 *       Negative overflow.  `val < -2**(numwords*(wordsize*CHAR_BIT-nails))`
 *
 *   - `-1` :
 *       Negative without overflow.
 *       `-2**(numwords*(wordsize*CHAR_BIT-nails)) <= val < 0`
 *
 *   - `0` : zero.  `val == 0`
 *
 *   - `1` :
 *       Positive without overflow.
 *       `0 < val < 2**(numwords*(wordsize*CHAR_BIT-nails))`
 *
 *   - `2` :
 *       Positive overflow.  `2**(numwords*(wordsize*CHAR_BIT-nails)) <= val`
 *
 * The value,  `-2**(numwords*(wordsize*CHAR_BIT-nails))`, is  representable in
 * 2's complement representation  but not representable in  absolute value.  So
 * `-1`  is returned  for the  value  if #INTEGER_PACK_2COMP  is specified  but
 * returns `-2` if #INTEGER_PACK_2COMP is not specified.
 *
 * The least significant words are filled in the buffer when overflow occur.
 */
int rb_integer_pack(VALUE val, void *words, size_t numwords, size_t wordsize, size_t nails, int flags);

RBIMPL_ATTR_NONNULL(())
/**
 * Import an integer from a buffer.
 *
 * @param[in]  words         Buffer to import.
 * @param[in]  numwords      Number of words of `words`.
 * @param[in]  wordsize      Number of bytes per word.
 * @param[in]  nails         Number   of  padding   bits  in   a  word.    Most
 *                           significant nails bits of each word are ignored.
 * @param[in]  flags         Bitwise   or  of   constants  whose   name  starts
 *                           "INTEGER_PACK_".
 * @exception  rb_eArgError  `numwords * wordsize` too big.
 *
 * Possible flags are:
 *
 *   - #INTEGER_PACK_MSWORD_FIRST:
 *       Interpret the first word as the most significant word.
 *
 *   - #INTEGER_PACK_LSWORD_FIRST:
 *       Interpret the first word as the least significant word.
 *
 *   - #INTEGER_PACK_MSBYTE_FIRST:
 *       Interpret the first byte in a word as the most significant byte in the
 *       word.
 *
 *   - #INTEGER_PACK_LSBYTE_FIRST:
 *       Interpret the  first byte in a  word as the least  significant byte in
 *       the word.
 *
 *   - #INTEGER_PACK_NATIVE_BYTE_ORDER:
 *       Either   #INTEGER_PACK_MSBYTE_FIRST    or   #INTEGER_PACK_LSBYTE_FIRST
 *       corresponding to the host's endian.
 *
 *   - #INTEGER_PACK_2COMP:
 *       Uses 2's complement representation.
 *
 *   - #INTEGER_PACK_LITTLE_ENDIAN: Shorthand of
 *       `INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_LSBYTE_FIRST`
 *
 *   - #INTEGER_PACK_BIG_ENDIAN: Shorthand of
 *       `INTEGER_PACK_MSWORD_FIRST|INTEGER_PACK_MSBYTE_FIRST`
 *
 *   - #INTEGER_PACK_FORCE_BIGNUM:
 *       Returns a bignum even if its value is representable as a fixnum.
 *
 *   - #INTEGER_PACK_NEGATIVE:
 *       Returns a  non-positive value.  (Returns a  non-negative value  if not
 *       specified.)
 *
 *   - #INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION:
 *       Uses generic implementation (for test and debug).
 *
 * @return  An  instance  of  ::rb_cInteger  whose  value  is  the  interpreted
 *          `words`.    The   range   of    the   result   value   depends   on
 *          #INTEGER_PACK_2COMP and #INTEGER_PACK_NEGATIVE.
 *
 * When #INTEGER_PACK_2COMP is not set:
 *
 *   - `0 <= val < 2**(numwords*(wordsize*CHAR_BIT-nails))` if
 *     `!INTEGER_PACK_NEGATIVE`
 *
 *   - `-2**(numwords*(wordsize*CHAR_BIT-nails)) < val <= 0` if
 *     `INTEGER_PACK_NEGATIVE`
 *
 * When #INTEGER_PACK_2COMP is set:
 *
 *   - `-2**(numwords*(wordsize*CHAR_BIT-nails)-1)` `<= val <=`
 *     `2**(numwords*(wordsize*CHAR_BIT-nails)-1)-1` if
 *     `!INTEGER_PACK_NEGATIVE`
 *
 *   - `-2**(numwords*(wordsize*CHAR_BIT-nails)) <= val <= -1` if
 *     `INTEGER_PACK_NEGATIVE`
 *
 * Passing  #INTEGER_PACK_2COMP   without  #INTEGER_PACK_NEGATIVE   means  sign
 * extension.  #INTEGER_PACK_2COMP  with #INTEGER_PACK_NEGATIVE  means assuming
 * the higher bits are `1`.
 *
 * Note   that  this   function  returns   0  when   `numwords`  is   zero  and
 * #INTEGER_PACK_2COMP is set but #INTEGER_PACK_NEGATIVE is not set.
 */
VALUE rb_integer_unpack(const void *words, size_t numwords, size_t wordsize, size_t nails, int flags);

/**
 * Calculates the number of bytes needed to represent the absolute value of the
 * passed integer.
 *
 * @param[in]   val            Integer   or  integer-like   object  which   has
 *                             `#to_int` method.
 * @param[out]  nlz_bits_ret   Number  of   leading  zero  bits  in   the  most
 *                             significant byte is returned if not `NULL`.
 * @exception   rb_eTypeError  `val` doesn't respond to `#to_int`.
 * @return      `((val_numbits * CHAR_BIT + CHAR_BIT - 1) / CHAR_BIT)`,   where
 *              val_numbits is the number of bits of `abs(val)`.
 * @post        If `nlz_bits_ret` is not `NULL`,
 *              `(return_value * CHAR_BIT - val_numbits)`    is    stored    in
 *              `*nlz_bits_ret`.  In this case,
 *              `0 <= *nlz_bits_ret < CHAR_BIT`.
 *
 * This function should not overflow.
 */
size_t rb_absint_size(VALUE val, int *nlz_bits_ret);

/**
 * Calculates the  number of words needed  represent the absolute value  of the
 * passed  integer.  Unlike  rb_absint_size() this  function can  overflow.  It
 * returns `(size_t)-1` then.
 *
 * @param[in]   val            Integer   or  integer-like   object  which   has
 *                             `#to_int` method.
 * @param[in]   word_numbits   Number of bits per word.
 * @param[out]  nlz_bits_ret   Number  of   leading  zero  bits  in   the  most
 *                             significant word is returned if not `NULL`.
 * @exception   rb_eTypeError  `val` doesn't respond to `#to_int`.
 * @retval      (size_t)-1     Overflowed.
 * @retval      otherwise
                `((val_numbits * CHAR_BIT + word_numbits - 1) / word_numbits)`,
 *              where val_numbits is the number of bits of `abs(val)`.
 * @post        If  `nlz_bits_ret` is  not  `NULL` and  there  is no  overflow,
 *              `(return_value * word_numbits - val_numbits)`   is  stored   in
 *              `*nlz_bits_ret`.  In this case,
 *              `0 <= *nlz_bits_ret < word_numbits.`
 *
 */
size_t rb_absint_numwords(VALUE val, size_t word_numbits, size_t *nlz_bits_ret);

/**
 * Tests `abs(val)` consists only of a bit or not.
 *
 * @param[in]   val            Integer   or  integer-like   object  which   has
 *                             `#to_int` method.
 * @exception   rb_eTypeError  `val` doesn't respond to `#to_int`.
 * @retval      1              `abs(val) == 1 << n` for some `n >= 0`.
 * @retval      0              Otherwise.
 *
 * rb_absint_singlebit_p() can  be used to  determine required buffer  size for
 * rb_integer_pack() used with #INTEGER_PACK_2COMP (two's complement).
 *
 * Following example  calculates number  of bits required  to represent  val in
 * two's complement number, without sign bit.
 *
 * ```CXX
 *   size_t size;
 *   int neg = FIXNUM_P(val) ? FIX2LONG(val) < 0 : BIGNUM_NEGATIVE_P(val);
 *   size = rb_absint_numwords(val, 1, NULL)
 *   if (size == (size_t)-1) ...overflow...
 *   if (neg && rb_absint_singlebit_p(val))
 *     size--;
 * ```
 *
 * Following example  calculates number of  bytes required to represent  val in
 * two's complement number, with sign bit.
 *
 * ```CXX
 *   size_t size;
 *   int neg = FIXNUM_P(val) ? FIX2LONG(val) < 0 : BIGNUM_NEGATIVE_P(val);
 *   int nlz_bits;
 *   size = rb_absint_size(val, &nlz_bits);
 *   if (nlz_bits == 0 && !(neg && rb_absint_singlebit_p(val)))
 *     size++;
 * ```
 */
int rb_absint_singlebit_p(VALUE val);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_BIGNUM_H */
