#ifndef RBIMPL_INTERN_RANDOM_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_RANDOM_H
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
 * @brief      MT19937 backended pseudo random number generator.
 * @see        Matsumoto,  M.,   Nishimura,  T.,  "Mersenne  Twister:   A  623-
 *             dimensionally   equidistributed   uniform  pseudorandom   number
 *             generator", ACM  Trans. on  Modeling and Computer  Simulation, 8
 *             (1): pp 3-30, 1998.  https://doi.org/10.1145/272991.272995
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* random.c */

/**
 * Generates a 32 bit random number.
 *
 * @return  A random number.
 * @note    Now  that  we  have  ractors,  the  RNG  behind  this  function  is
 *          per-ractor.
 */
unsigned int rb_genrand_int32(void);

/**
 * Generates a `double` random number.
 *
 * @return  A random number.
 * @note    This function shares the RNG with rb_genrand_int32().
 */
double rb_genrand_real(void);

/**
 * Resets the RNG behind rb_genrand_int32()/rb_genrand_real().
 *
 * @post  The (now per-ractor) default RNG's internal state is cleared.
 */
void rb_reset_random_seed(void);

/**
 * Generates a String of random bytes.
 *
 * @param[in,out]  rnd  An instance of ::rb_cRandom.
 * @param[in]      n    Requested number of bytes.
 * @return         An instance of ::rb_cString, of binary, of `n` bytes length,
 *                 whose contents are random bits.
 *
 * @internal
 *
 * @shyouhei doesn't know if this is an  Easter egg or an official feature, but
 * this function can  take a wider range of objects,  such as `Socket::Ifaddr`.
 * The arguments are just silently ignored and the default RNG is used instead,
 * if they are non-RNG.
 */
VALUE rb_random_bytes(VALUE rnd, long n);

/**
 * Identical to rb_genrand_int32(), except it generates using the passed RNG.
 *
 * @param[in,out]  rnd  An instance of ::rb_cRandom.
 * @return         A random number.
 */
unsigned int rb_random_int32(VALUE rnd);

/**
 * Identical to rb_genrand_real(), except it generates using the passed RNG.
 *
 * @param[in,out]  rnd  An instance of ::rb_cRandom.
 * @return         A random number.
 */
double rb_random_real(VALUE rnd);

/**
 * Identical  to  rb_genrand_ulong_limited(),  except it  generates  using  the
 * passed RNG.
 *
 * @param[in,out]  rnd    An instance of ::rb_cRandom.
 * @param[in]      limit  Max possible return value.
 * @return         A random number, distributed in `[0, limit]` interval.
 * @note           Note it can return `limit`.
 * @note           Whether  the  return  value  distributes  uniformly  in  the
 *                 interval or not depends on  how the argument RNG behaves; at
 *                 least in case of MT19937 it does.
 */
unsigned long rb_random_ulong_limited(VALUE rnd, unsigned long limit);

/**
 * Generates a random number whose upper limit is `i`.
 *
 * @param[in]  i  Max possible return value.
 * @return     A random number, uniformly distributed in `[0, limit]` interval.
 * @note       Note it can return `i`.
 */
unsigned long rb_genrand_ulong_limited(unsigned long i);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_RANDOM_H */
