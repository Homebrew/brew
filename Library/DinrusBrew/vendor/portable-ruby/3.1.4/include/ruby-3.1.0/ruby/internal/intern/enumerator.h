#ifndef RBIMPL_INTERN_ENUMERATOR_H                   /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_ENUMERATOR_H
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
 * @brief      Public APIs related to ::rb_cEnumerator.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/intern/eval.h" /* rb_frame_this_func */
#include "ruby/internal/iterator.h"    /* rb_block_given_p */
#include "ruby/internal/symbol.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * This is the type of functions that rb_enumeratorize_with_size() expects.  In
 * theory an enumerator can have indefinite number of elements, but in practice
 * it often is  the case we can  compute the size of  an enumerator beforehand.
 * If your enumerator has such property, supply a function that calculates such
 * values.
 *
 * @param[in]  recv  The original receiver of the enumerator.
 * @param[in]  argv  Arguments passed to `Object#enum_for` etc.
 * @param[in]  eobj  The enumerator object.
 * @return     The size of `eobj`, in ::rb_cNumeric, or ::RUBY_Qnil if the size
 *             is not known until we actually iterate.
 */
typedef VALUE rb_enumerator_size_func(VALUE recv, VALUE argv, VALUE eobj);

/**
 * Decomposed   `Enumerator::ArithmeicSequence`.   This   is   a  subclass   of
 * ::rb_cEnumerator,  which  represents  a  sequence  of  numbers  with  common
 * difference.  Internal  data structure of the  class is opaque to  users, but
 * you can obtain a decomposed one using rb_arithmetic_sequence_extract().
 */
typedef struct {
    VALUE begin;          /**< "Left" or "lowest" endpoint of the sequence. */
    VALUE end;            /**< "Right" or "highest" endpoint of the sequence.*/
    VALUE step;           /**< Step between a sequence. */
    int exclude_end;      /**< Whether the endpoint is open or closed.  */
} rb_arithmetic_sequence_components_t;

/* enumerator.c */

/**
 * Constructs an enumerator.  This roughly resembles `Object#enum_for`.
 *
 * @param[in]  recv           A receiver of `meth`.
 * @param[in]  meth           Method ID in a symbol object.
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           Arguments passed to `meth`.
 * @exception  rb_eTypeError  `meth` is not an instance of ::rb_cSymbol.
 * @return     A  new   instance  of  ::rb_cEnumerator  which,   when  yielded,
 *             enumerates by calling `meth` on `recv` with `argv`.
 */
VALUE rb_enumeratorize(VALUE recv, VALUE meth, int argc, const VALUE *argv);

/**
 * Identical  to rb_enumeratorize(),  except you  can additionally  specify the
 * size function of return value.
 *
 * @param[in]  recv           A receiver of `meth`.
 * @param[in]  meth           Method ID in a symbol object.
 * @param[in]  argc           Number of objects of `argv`.
 * @param[in]  argv           Arguments passed to `meth`.
 * @param[in]  func           Size calculator.
 * @exception  rb_eTypeError  `meth` is not an instance of ::rb_cSymbol.
 * @return     A  new   instance  of  ::rb_cEnumerator  which,   when  yielded,
 *             enumerates by calling `meth` on `recv` with `argv`.
 * @note       `func` can be zero, which means the size is unknown.
 */
VALUE rb_enumeratorize_with_size(VALUE recv, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *func);

/**
 * Identical  to rb_enumeratorize_with_func(),  except you  can specify  how to
 * handle the last element of the given array.
 *
 * @param[in]  recv             A receiver of `meth`.
 * @param[in]  meth             Method ID in a symbol object.
 * @param[in]  argc             Number of objects of `argv`.
 * @param[in]  argv             Arguments passed to `meth`.
 * @param[in]  func             Size calculator.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @exception  rb_eTypeError    `meth` is not an instance of ::rb_cSymbol.
 * @return     A  new   instance  of  ::rb_cEnumerator  which,   when  yielded,
 *             enumerates by calling `meth` on `recv` with `argv`.
 * @note       `func` can be zero, which means the size is unknown.
 */
VALUE rb_enumeratorize_with_size_kw(VALUE recv, VALUE meth, int argc, const VALUE *argv, rb_enumerator_size_func *func, int kw_splat);

RBIMPL_ATTR_NONNULL(())
/**
 * Extracts components of the passed arithmetic  sequence.  This can be seen as
 * an extended version of rb_range_values().
 *
 * @param[in]   as   Target instance of `Enumerator::ArithmericSequence`.
 * @param[out]  buf  Decomposed results buffer.
 * @return      0    `as` is not `Enumerator::ArithmericSequence`.
 * @return      1    Success.
 * @post        `buf` is filled.
 */
int rb_arithmetic_sequence_extract(VALUE as, rb_arithmetic_sequence_components_t *buf);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical   to  rb_range_beg_len(),   except   it  takes   an  instance   of
 * `Enumerator::ArithmericSequence`.
 *
 * @param[in]   as              An `Enumerator::ArithmericSequence` instance.
 * @param[out]  begp            Return value buffer.
 * @param[out]  lenp            Return value buffer.
 * @param[out]  stepp           Return value buffer.
 * @param[in]   len             Updated length.
 * @param[in]   err             In case `len` is out of range...
 *                                - `0`: returns ::RUBY_Qnil.
 *                                - `1`: raises  ::rb_eRangeError.
 *                                - `2`: `beg` and `len` expanded accordingly.
 * @exception   rb_eRangeError  `as` cannot fit into `long`.
 * @retval      RUBY_Qfalse     `as` is not `Enumerator::ArithmericSequence`.
 * @retval      RUBY_Qnil       `len` is out of `as` but `err` is zero.
 * @retval      RUBY_Qtrue      Otherwise.
 * @post        `beg` is the (possibly updated) left endpoint.
 * @post        `len` is the (possibly updated) length of the range.
 *
 * @internal
 *
 * Currently no 3rd party applications of this function is found.  But that can
 * be because this function is relatively new.
 */
VALUE rb_arithmetic_sequence_beg_len_step(VALUE as, long *begp, long *lenp, long *stepp, long len, int err);

RBIMPL_SYMBOL_EXPORT_END()

/** @cond INTERNAL_MACRO */
#ifndef RUBY_EXPORT
# define rb_enumeratorize_with_size(obj, id, argc, argv, size_fn) \
    rb_enumeratorize_with_size(obj, id, argc, argv, (rb_enumerator_size_func *)(size_fn))
# define rb_enumeratorize_with_size_kw(obj, id, argc, argv, size_fn, kw_splat) \
    rb_enumeratorize_with_size_kw(obj, id, argc, argv, (rb_enumerator_size_func *)(size_fn), kw_splat)
#endif
/** @endcond */

/**
 * This is  an implementation detail of  #RETURN_SIZED_ENUMERATOR().  You could
 * use it directly, but can hardly be handy.
 *
 * @param[in]  obj      A receiver.
 * @param[in]  argc     Number of objects of `argv`.
 * @param[in]  argv     Arguments passed to the current method.
 * @param[in]  size_fn  Size calculator.
 * @return     A  new   instance  of  ::rb_cEnumerator  which,   when  yielded,
 *             enumerates by calling the current method on `recv` with `argv`.
 */
#define SIZED_ENUMERATOR(obj, argc, argv, size_fn)                  \
    rb_enumeratorize_with_size((obj), ID2SYM(rb_frame_this_func()), \
                               (argc), (argv), (size_fn))

/**
 * This  is an  implementation  detail  of #RETURN_SIZED_ENUMERATOR_KW().   You
 * could use it directly, but can hardly be handy.
 *
 * @param[in]  obj              A receiver.
 * @param[in]  argc             Number of objects of `argv`.
 * @param[in]  argv             Arguments passed to the current method.
 * @param[in]  size_fn          Size calculator.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @return     A  new   instance  of  ::rb_cEnumerator  which,   when  yielded,
 *             enumerates by calling the current method on `recv` with `argv`.
 */
#define SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat)        \
    rb_enumeratorize_with_size_kw((obj), ID2SYM(rb_frame_this_func()), \
                                  (argc), (argv), (size_fn), (kw_splat))

/**
 * This roughly resembles `return enum_for(__callee__) unless block_given?`.
 *
 * @param[in]  obj      A receiver.
 * @param[in]  argc     Number of objects of `argv`.
 * @param[in]  argv     Arguments passed to the current method.
 * @param[in]  size_fn  Size calculator.
 * @note       This macro may return inside.
 */
#define RETURN_SIZED_ENUMERATOR(obj, argc, argv, size_fn) do {          \
        if (!rb_block_given_p())                                        \
            return SIZED_ENUMERATOR(obj, argc, argv, size_fn);          \
    } while (0)


/**
 * Identical  to  #RETURN_SIZED_ENUMERATOR(), except  you  can  specify how  to
 * handle the last element of the given array.
 *
 * @param[in]  obj              A receiver.
 * @param[in]  argc             Number of objects of `argv`.
 * @param[in]  argv             Arguments passed to the current method.
 * @param[in]  size_fn          Size calculator.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @note       This macro may return inside.
 */
#define RETURN_SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat) do { \
        if (!rb_block_given_p())                                            \
            return SIZED_ENUMERATOR_KW(obj, argc, argv, size_fn, kw_splat);              \
    } while (0)

/**
 * Identical to #RETURN_SIZED_ENUMERATOR(), except its size is unknown.
 *
 * @param[in]  obj   A receiver.
 * @param[in]  argc  Number of objects of `argv`.
 * @param[in]  argv  Arguments passed to the current method.
 * @note       This macro may return inside.
 */
#define RETURN_ENUMERATOR(obj, argc, argv) \
    RETURN_SIZED_ENUMERATOR(obj, argc, argv, 0)

/**
 * Identical to #RETURN_SIZED_ENUMERATOR_KW(), except  its size is unknown.  It
 * can also be seen as a  routine identical to #RETURN_ENUMERATOR(), except you
 * can specify how to handle the last element of the given array.
 *
 * @param[in]  obj              A receiver.
 * @param[in]  argc             Number of objects of `argv`.
 * @param[in]  argv             Arguments passed to the current method.
 * @param[in]  kw_splat         Handling of keyword parameters:
 *   - RB_NO_KEYWORDS           `argv`'s last is not a keyword argument.
 *   - RB_PASS_KEYWORDS         `argv`'s last is a keyword argument.
 *   - RB_PASS_CALLED_KEYWORDS  it depends if there is a passed block.
 * @note       This macro may return inside.
 */
#define RETURN_ENUMERATOR_KW(obj, argc, argv, kw_splat) \
    RETURN_SIZED_ENUMERATOR_KW(obj, argc, argv, 0, kw_splat)

#endif /* RBIMPL_INTERN_ENUMERATOR_H */
