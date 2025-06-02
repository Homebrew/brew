#ifndef RUBY_RANDOM_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_RANDOM_H 1
/**
 * @file
 * @date       Sat May  7 11:51:14 JST 2016
 * @copyright  2007-2020 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 *
 * This  is a  set of  APIs  to roll  your  own subclass  of ::rb_cRandom.   An
 * illustrative    example     of    such     PRNG    can    be     found    at
 * `ext/-test-/random/loop.c`.
 */

#include "ruby/ruby.h"

/*
 * version
 * 0: before versioning; deprecated
 * 1: added version, flags and init_32bit function
 */
#define RUBY_RANDOM_INTERFACE_VERSION_MAJOR 1
#define RUBY_RANDOM_INTERFACE_VERSION_MINOR 0

#define RUBY_RANDOM_PASTE_VERSION_SUFFIX(x, y, z) x##_##y##_##z
#define RUBY_RANDOM_WITH_VERSION_SUFFIX(name, major, minor) \
    RUBY_RANDOM_PASTE_VERSION_SUFFIX(name, major, minor)
#define rb_random_data_type \
    RUBY_RANDOM_WITH_VERSION_SUFFIX(rb_random_data_type, \
                                    RUBY_RANDOM_INTERFACE_VERSION_MAJOR, \
                                    RUBY_RANDOM_INTERFACE_VERSION_MINOR)
#define RUBY_RANDOM_INTERFACE_VERSION_INITIALIZER \
    {RUBY_RANDOM_INTERFACE_VERSION_MAJOR, RUBY_RANDOM_INTERFACE_VERSION_MINOR}
#define RUBY_RANDOM_INTERFACE_VERSION_MAJOR_MAX 0xff
#define RUBY_RANDOM_INTERFACE_VERSION_MINOR_MAX 0xff

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Base components of the random interface.
 *
 * @internal
 *
 * Ideally this  could be an  empty class if  we could assume  C++, but in  C a
 * struct must have at least one field.
 */
struct rb_random_struct {
    /** Seed, passed through e.g. `Random.new` */
    VALUE seed;
};
typedef struct rb_random_struct rb_random_t; /**< @see ::rb_random_struct */

RBIMPL_ATTR_NONNULL(())
/**
 * This is the type of functions called when your random object is initialised.
 * Passed buffer  is the seed  object basically.  But in  Ruby a number  can be
 * really big.  This type of functions accept  such big integers as a series of
 * machine words.
 *
 * @param[out]  rng  Your random struct to fill in.
 * @param[in]   buf  Seed, maybe converted from a bignum.
 * @param[in]   len  Number of words of `buf`.
 * @post        `rng` is initialised using the passed seeds.
 */
typedef void rb_random_init_func(rb_random_t *rng, const uint32_t *buf, size_t len);

RBIMPL_ATTR_NONNULL(())
/**
 * This is the type of functions called when your random object is initialised.
 * Passed data is the seed integer.
 *
 * @param[out]  rng  Your random struct to fill in.
 * @param[in]   data Seed, single word.
 * @post        `rng` is initialised using the passed seeds.
 */
typedef void rb_random_init_int32_func(rb_random_t *rng, uint32_t data);

RBIMPL_ATTR_NONNULL(())
/**
 * This is the type of functions  called from your object's `#rand` method.
 *
 * @param[out]  rng  Your random struct to extract an integer from.
 * @return      A random number.
 * @post        `rng` is consumed somehow.
 */
typedef unsigned int rb_random_get_int32_func(rb_random_t *rng);

RBIMPL_ATTR_NONNULL(())
/**
 * This is the type of functions called from your object's `#bytes` method.
 *
 * @param[out]  rng  Your random struct to extract an integer from.
 * @param[out]  buf  Return buffer of at least `len` bytes length.
 * @param[in]   len  Number of bytes of `buf`.
 * @post        `rng` is consumed somehow.
 * @post        `buf` is filled with random bytes.
 */
typedef void rb_random_get_bytes_func(rb_random_t *rng, void *buf, size_t len);

RBIMPL_ATTR_NONNULL(())
/**
 * This is the type of functions called from your object's `#rand` method.
 *
 * @param[out]  rng   Your random struct to extract an integer from.
 * @param[in]   excl  Pass nonzero value here to indicate you don't want 1.0.
 * @return      A random number of range 0.0 to 1.0.
 * @post        `rng` is consumed somehow.
 */
typedef double rb_random_get_real_func(rb_random_t *rng, int excl);

/** PRNG algorithmic interface, analogous to Ruby level classes. */
typedef struct {
    /** Number of bits of seed numbers. */
    size_t default_seed_bits;

    /**
     * Major/minor versions of this interface
     */
    struct {
        uint8_t major, minor;
    } version;

    /**
     * Reserved flags
     */
    uint16_t flags;

    /** Function to initialize from uint32_t array. */
    rb_random_init_func *init;

    /** Function to initialize from single uint32_t. */
    rb_random_init_int32_func *init_int32;

    /** Function to obtain a random integer. */
    rb_random_get_int32_func *get_int32;

    /**
     * Function to obtain a series of random bytes.  If your PRNG have a native
     * method to  yield arbitrary number of  bytes use that to  implement this.
     * But  in   case  you  lack   such  things,  you   can  do  so   by  using
     * rb_rand_bytes_int32()
     *
     * ```CXX
     * extern rb_random_get_int32_func your_get_int32_func;
     *
     * void
     * your_get_byes_func(rb_random_t *rng, void *buf, size_t len)
     * {
     *     rb_rand_bytes_int32(your_get_int32_func, rng, buf, len);
     * }
     * ```
     */
    rb_random_get_bytes_func *get_bytes;

    /**
     * Function to obtain  a random double.  If your PRNG  have a native method
     * to yield a floating point random number use that to implement this.  But
     * in   case   you  lack   such   things,   you   can   do  so   by   using
     * rb_int_pair_to_real().
     *
     * ```CXX
     * extern rb_random_get_int32_func your_get_int32_func;
     *
     * void
     * your_get_real_func(rb_random_t *rng, int excl)
     * {
     *     auto a = your_get_int32_func(rng);
     *     auto b = your_get_int32_func(rng);
     *     return rb_int_pair_to_real(a, b, excl);
     * }
     * ```
     */
    rb_random_get_real_func *get_real;
} rb_random_interface_t;

/**
 * This utility macro defines 4 functions named prefix_init, prefix_init_int32,
 * prefix_get_int32, prefix_get_bytes.
 */
#define RB_RANDOM_INTERFACE_DECLARE(prefix) \
    static void prefix##_init(rb_random_t *, const uint32_t *, size_t); \
    static void prefix##_init_int32(rb_random_t *, uint32_t); \
    static unsigned int prefix##_get_int32(rb_random_t *); \
    static void prefix##_get_bytes(rb_random_t *, void *, size_t)

/**
 * Identical   to   #RB_RANDOM_INTERFACE_DECLARE   except  it   also   declares
 * prefix_get_real.
 */
#define RB_RANDOM_INTERFACE_DECLARE_WITH_REAL(prefix) \
    RB_RANDOM_INTERFACE_DECLARE(prefix); \
    static double prefix##_get_real(rb_random_t *, int)

/**
 * This    utility    macro   expands    to    the    names   declared    using
 * #RB_RANDOM_INTERFACE_DECLARE.    Expected   to   be   used   inside   of   a
 * ::rb_random_interface_t initialiser:
 *
 * ```CXX
 * RB_RANDOM_INTERFACE_DECLARE(foo);
 *
 * static inline constexpr rb_random_interface_t foo_interface = {
 *     32768, // bits
 *     RB_RANDOM_INTERFACE_DEFINE(foo),
 * };
 * ```
 */
#define RB_RANDOM_INTERFACE_DEFINE(prefix) \
    RUBY_RANDOM_INTERFACE_VERSION_INITIALIZER, 0, \
    prefix##_init, \
    prefix##_init_int32, \
    prefix##_get_int32, \
    prefix##_get_bytes

/**
 * Identical   to   #RB_RANDOM_INTERFACE_DEFINE    except   it   also   defines
 * prefix_get_real.
 */
#define RB_RANDOM_INTERFACE_DEFINE_WITH_REAL(prefix) \
    RB_RANDOM_INTERFACE_DEFINE(prefix), \
    prefix##_get_real

#define RB_RANDOM_DEFINE_INIT_INT32_FUNC(prefix) \
    static void prefix##_init_int32(rb_random_t *rnd, uint32_t data) \
    { \
        prefix##_init(rnd, &data, 1); \
    }

#if defined _WIN32 && !defined __CYGWIN__
typedef rb_data_type_t rb_random_data_type_t;
# define RB_RANDOM_PARENT 0
#else

/** This is the type of ::rb_random_data_type. */
typedef const rb_data_type_t rb_random_data_type_t;

/**
 * This utility macro can be used when you define your own PRNG type:
 *
 * ```CXX
 * static inline constexpr rb_random_interface_t your_if = {
 *     0, RB_RANDOM_INTERFACE_DEFINE(your),
 * };
 *
 * static inline constexpr rb_random_data_type_t your_prng_type = {
 *     "your PRNG",
 *     { rb_random_mark, },
 *     RB_RANDOM_PARENT,                 // <<-- HERE
 *     &your_if,
 *     0,
 * }
 * ```
 */
# define RB_RANDOM_PARENT &rb_random_data_type
#endif

/**
 * This macro  is expected  to be  called exactly  once at  the beginning  of a
 * program, possibly from  inside of your `Init_Foo()`  function.  Depending on
 * platforms #RB_RANDOM_PARENT  can require  a fixup.   This routine  does that
 * when necessary.
 */
#define RB_RANDOM_DATA_INIT_PARENT(random_data) \
    rbimpl_random_data_init_parent(&random_data)

/**
 * This   is    the   implementation   of    ::rb_data_type_struct::dmark   for
 * ::rb_random_data_type.  In case  your PRNG does not involve  Ruby objects at
 * all (which is quite likely), you can simply reuse it.
 *
 * @param[out]  ptr  Target to mark, which is a ::rb_random_t this case.
 */
void rb_random_mark(void *ptr);

/**
 * Initialises  an allocated  ::rb_random_t instance.   Call it  from your  own
 * initialiser appropriately.
 *
 * @param[out]  rnd  Your PRNG's base part.
 * @post        `rnd` is filled with an initial state.
 */
void rb_random_base_init(rb_random_t *rnd);

/**
 * Generates a 64 bit floating point number by concatenating two 32bit unsigned
 * integers.
 *
 * @param[in]  a     Most significant 32 bits of the result.
 * @param[in]  b     Least significant 32 bits of the result.
 * @param[in]  excl  Whether the result should exclude 1.0 or not.
 * @return     A double, whose range is either `[0, 1)` or `[0, 1]`.
 * @see        ::rb_random_interface_t::get_real()
 *
 * @internal
 *
 * This in fact has nothing to do with PRNGs.
 */
double rb_int_pair_to_real(uint32_t a, uint32_t b, int excl);

/**
 * Repeatedly calls  the passed function over  and over again until  the passed
 * buffer is filled with random bytes.
 *
 * @param[in]   func  Generator function.
 * @param[out]  prng  Passed as-is to `func`.
 * @param[out]  buff  Return buffer.
 * @param[in]   size  Number of words of `buff`.
 * @post        `buff` is filled with random bytes.
 * @post        `prng` is updated by `func`.
 * @see        ::rb_random_interface_t::get_bytes()
 */
void rb_rand_bytes_int32(rb_random_get_int32_func *func, rb_random_t *prng, void *buff, size_t size);

/**
 * The data that  holds the backend type of ::rb_cRandom.   Used as your PRNG's
 * ::rb_data_type_struct::parent.
 */
RUBY_EXTERN const rb_data_type_t rb_random_data_type;

RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/* :TODO: can this function be __attribute__((returns_nonnull)) or not? */
/**
 * Queries the interface of the passed random object.
 *
 * @param[in]  obj  An instance (of a subclass) of ::rb_cRandom.
 * @return     Its corresponding ::rb_random_interface_t interface.
 */
static inline const rb_random_interface_t *
rb_rand_if(VALUE obj)
{
    RBIMPL_ASSERT_OR_ASSUME(RTYPEDDATA_P(obj));
    const struct rb_data_type_struct *t = RTYPEDDATA_TYPE(obj);
    const void *ret = t->data;
    return RBIMPL_CAST((const rb_random_interface_t *)ret);
}

RBIMPL_ATTR_NOALIAS()
/**
 * @private
 *
 * This  is an  implementation detail  of #RB_RANDOM_DATA_INIT_PARENT.   People
 * don't use it directly.
 *
 * @param[out]  random_data  Region to fill.
 * @post        ::rb_random_data_type is filled appropriately.
 */
static inline void
rbimpl_random_data_init_parent(rb_random_data_type_t *random_data)
{
#if defined _WIN32 && !defined __CYGWIN__
    random_data->parent = &rb_random_data_type;
#endif
}

#endif /* RUBY_RANDOM_H */
