#ifndef RBIMPL_RTYPEDDATA_H                          /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RTYPEDDATA_H
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
 * @brief      Defines struct ::RTypedData.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/internal/assume.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/flag_enum.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/core/rdata.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/error.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value_type.h"

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define HAVE_TYPE_RB_DATA_TYPE_T     1

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define HAVE_RB_DATA_TYPE_T_FUNCTION 1

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define HAVE_RB_DATA_TYPE_T_PARENT   1

/**
 * This is a  value you can set to  ::rb_data_type_struct::dfree.  Setting this
 * means the data was allocated using ::ruby_xmalloc() (or variants), and shall
 * be freed using ::ruby_xfree().
 *
 * @warning  Do not  use this  if you  want to use  system malloc,  because the
 *           system  and  Ruby  might  or  might  not  share  the  same  malloc
 *           implementation.
 */
#define RUBY_TYPED_DEFAULT_FREE      RUBY_DEFAULT_FREE

/**
 * This is a  value you can set to  ::rb_data_type_struct::dfree.  Setting this
 * means the data  is managed by someone else, like,  statically allocated.  Of
 * course you are on your own then.
 */
#define RUBY_TYPED_NEVER_FREE        RUBY_NEVER_FREE

/**
 * Convenient casting macro.
 *
 * @param   obj  An object, which is in fact an ::RTypedData.
 * @return  The passed object casted to ::RTypedData.
 */
#define RTYPEDDATA(obj)              RBIMPL_CAST((struct RTypedData *)(obj))

/**
 * Convenient getter macro.
 *
 * @param   v  An object, which is in fact an ::RTypedData.
 * @return  The passed object's ::RTypedData::data field.
 */
#define RTYPEDDATA_DATA(v)           (RTYPEDDATA(v)->data)

/** @old{rb_check_typeddata} */
#define Check_TypedStruct(v, t)      \
    rb_check_typeddata(RBIMPL_CAST((VALUE)(v)), (t))

/** @cond INTERNAL_MACRO */
#define RTYPEDDATA_P                 RTYPEDDATA_P
#define RTYPEDDATA_TYPE              RTYPEDDATA_TYPE
#define RUBY_TYPED_FREE_IMMEDIATELY  RUBY_TYPED_FREE_IMMEDIATELY
#define RUBY_TYPED_FROZEN_SHAREABLE  RUBY_TYPED_FROZEN_SHAREABLE
#define RUBY_TYPED_WB_PROTECTED      RUBY_TYPED_WB_PROTECTED
#define RUBY_TYPED_PROMOTED1         RUBY_TYPED_PROMOTED1
/** @endcond */

/**
 * @private
 *
 * Bits for rb_data_type_struct::flags.
 */
enum
RBIMPL_ATTR_FLAG_ENUM()
rbimpl_typeddata_flags {
    /**
     * This flag has something to do  with Ruby's global interpreter lock.  For
     * maximum  safety, Ruby  locks  the  entire VM  during  GC.  However  your
     * callback functions  could unintentionally  unlock it, for  instance when
     * they try to flush an IO  buffer.  Such operations are dangerous (threads
     * then  run alongside  of GC).   By  default, to  prevent those  scenario,
     * callbacks are deferred until the GC engine is 100% sure threads can run.
     * This flag skips  that; structs with it are deallocated  during the sweep
     * phase.
     *
     * Using this  flag needs deep understanding  of both GC and  threads.  You
     * would better leave it unspecified.
     */
    RUBY_TYPED_FREE_IMMEDIATELY = 1,

    /**
     * This flag has something to do with Ractor.  Multiple Ractors run without
     * protecting each  other.  Sharing  an object  among Ractors  is basically
     * dangerous,  disabled by  default.   This  flag is  used  to bypass  that
     * restriction.  but  setting it is not  enough.  In addition to  do so, an
     * object    also    has    to    be   frozen,    and    be    passed    to
     * rb_ractor_make_shareable() before being  actually shareable.  Of course,
     * you have to manually prevent race conditions then.
     *
     * Using this  flag needs deep understanding  of multithreaded programming.
     * You would better leave it unspecified.
     */
    RUBY_TYPED_FROZEN_SHAREABLE = RUBY_FL_SHAREABLE,

    /**
     * This flag  has something to do  with our garbage collector.   These days
     * ruby  objects are  "generational".  There  are those  who are  young and
     * those who are old.  Young objects are prone to die; monitored relatively
     * extensively by  the garbage  collector.  OTOH old  objects tend  to live
     * longer.  They  are relatively rarely considered.   This basically works.
     * But there is one  tweak that has to be exercised.   When an elder object
     * has reference(s)  to younger  one(s), that  referenced objects  must not
     * die.  In order  to detect additions of such  references, old generations
     * are  protected by  write  barriers.   It is  a  very  difficult hack  to
     * appropriately  insert  write  barriers everywhere.   This  mechanism  is
     * disabled by default for 3rd party  extensions (they never get aged).  By
     * specifying this  flag you  can enable the  generational feature  to your
     * data structure.  Of  course, you have to manually  insert write barriers
     * then.
     *
     * Using this  flag needs deep understanding  of GC internals, often at the
     * level of source code.  You would better leave it unspecified.
     */
    RUBY_TYPED_WB_PROTECTED     = RUBY_FL_WB_PROTECTED, /* THIS FLAG DEPENDS ON Ruby version */

    /**
     * This flag  is mysterious.  It seems  nobody is currently using  it.  The
     * intention of this flag is also unclear.  We need further investigations.
     */
    RUBY_TYPED_PROMOTED1        = RUBY_FL_PROMOTED1     /* THIS FLAG DEPENDS ON Ruby version */
};

/**
 * This  is the  struct that  holds necessary  info for  a struct.   It roughly
 * resembles a Ruby level class;  multiple objects can share a ::rb_data_type_t
 * instance.
 */
typedef struct rb_data_type_struct rb_data_type_t;

/** @copydoc rb_data_type_t */
struct rb_data_type_struct {

    /**
     * Name of  structs of this  kind.  This  is used for  diagnostic purposes.
     * This has  to be unique  in the  process, but doesn't  has to be  a valid
     * C/Ruby identifier.
     */
    const char *wrap_struct_name;

    /** Function pointers.  Resembles C++ `vtbl`.*/
    struct {

        /**
         * This function  is called when  the object is experiencing  GC marks.
         * If it  contains references to other  Ruby objects, you need  to mark
         * them also.  Otherwise GC will smash your data.
         *
         * @see      rb_gc_mark()
         * @warning  This  is called  during GC  runs.  Object  allocations are
         *           impossible at that moment (that is why GC runs).
         */
        RUBY_DATA_FUNC dmark;

        /**
         * This function is called when the object is no longer used.  You need
         * to do whatever necessary to avoid memory leaks.
         *
         * @warning  This  is called  during GC  runs.  Object  allocations are
         *           impossible at that moment (that is why GC runs).
         */
        RUBY_DATA_FUNC dfree;

        /**
         * This function is to query the size of the underlying memory regions.
         *
         * @internal
         *
         * This  function  has  only  one   usage,  which  is  form  inside  of
         * `ext/objspace`.
         */
        size_t (*dsize)(const void *);

        /**
         * This  function  is  called  when  the  object  is  relocated.   Like
         * ::rb_data_type_struct::dmark, you need to  update references to Ruby
         * objects inside of your structs.
         *
         * @see      rb_gc_location()
         * @warning  This  is called  during GC  runs.  Object  allocations are
         *           impossible at that moment (that is why GC runs).
         */
        RUBY_DATA_FUNC dcompact;

        /**
         * This field  is reserved for future  extension.  For now, it  must be
         * filled with zeros.
         */
        void *reserved[1]; /* For future extension.
                              This array *must* be filled with ZERO. */
    } function;

    /**
     * Parent  of  this  class.   Sometimes  C  structs  have  inheritance-like
     * relationships.  An example is `struct sockaddr`  and its family.  If you
     * design such things,  make ::rb_data_type_t for each of  them and connect
     * using this field.   Ruby can then transparently cast your  data back and
     * forth when you call #TypedData_Get_Struct().
     *
     * ```CXX
     * struct parent { };
     * static inline const rb_data_type_t parent_type = {
     *     .wrap_struct_name = "parent",
     * };
     *
     * struct child: public parent { };
     * static inline const rb_data_type_t child_type = {
     *     .wrap_struct_name = "child",
     *     .parent = &parent_type,
     * };
     *
     * // This function can take both parent_class and child_class.
     * static inline struct parent *
     * get_parent(VALUE v)
     * {
     *     struct parent *p;
     *     TypedData_Get_Struct(v, parent_type, struct parent, p);
     *     return p;
     * }
     * ```
     */
    const rb_data_type_t *parent;

    /**
     * Type-specific static data.   This area can be used for  any purpose by a
     * programmer who define the type.  Ruby does not manage this at all.
     */
    void *data;        /* This area can be used for any purpose
                          by a programmer who define the type. */

    /**
     * Type-specific behavioural  characteristics.  This is a  bitfield.  It is
     * an EXTREMELY  WISE IDEA to  leave this field  blank.  It is  designed so
     * that setting  zero is the safest  thing to do.   If you risk to  set any
     * bits on, you have to know exactly what you are doing.
     *
     * @internal
     *
     * Why it has to be a ::VALUE?  @shyouhei doesn't understand the design.
     */
    VALUE flags;       /* RUBY_FL_WB_PROTECTED */
};

/**
 * "Typed" user data.   By using this, extension libraries can  wrap a C struct
 * to make it visible from Ruby.  For  instance if you have a `struct timeval`,
 * and you want users to use it,
 *
 * ```CXX
 * static inline const rb_data_type_t timeval_type = {
 *     // Note that unspecified fields are 0-filled by default.
 *     .wrap_struct_name = "timeval",
 *     .function = {
 *         .dmark = nullptr,                 // no need to mark
 *         .dfree = RUBY_TYPED_DEFAULT_FREE, // use ruby_xfree()
 *         .dsize = [](auto) {
 *             return sizeof(struct timeval);
 *         },
 *     },
 * };
 *
 * extern "C" void
 * Init_timeval(void)
 * {
 *     auto klass = rb_define_class("YourName", rb_cObject);
 *
 *     rb_define_alloc_func(klass, [](auto klass) {
 *         struct timeval *t;
 *         auto ret = TypedData_Make_Struct(
 *            klass, struct timeval, &timeval_type, t);
 *
 *         if (auto i = gettimeofday(t, nullptr); i == -1) {
 *             rb_sys_fail("gettimeofday(3)");
 *         }
 *         else {
 *             return ret;
 *         }
 *     });
 * }
 * ```
 */
struct RTypedData {

    /** The part that all ruby objects have in common. */
    struct RBasic basic;

    /**
     * This field  stores various  information about how  Ruby should  handle a
     * data.   This roughly  resembles a  Ruby level  class (apart  from method
     * definition etc.)
     */
    const rb_data_type_t *type;

    /**
     * This has to be always 1.
     *
     * @internal
     *
     * Why, then, this is not a const ::VALUE?
     */
    VALUE typed_flag;

    /** Pointer to the actual C level struct that you want to wrap. */
    void *data;
};

RBIMPL_SYMBOL_EXPORT_BEGIN()
RBIMPL_ATTR_NONNULL((3))
/**
 * This is the primitive way to wrap an existing C struct into ::RTypedData.
 *
 * @param[in]  klass          Ruby level class of the returning object.
 * @param[in]  datap          Pointer to the target C struct.
 * @param[in]  type           The characteristics of the passed data.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     An allocated object that wraps `datap`.
 */
VALUE rb_data_typed_object_wrap(VALUE klass, void *datap, const rb_data_type_t *type);

/**
 * Identical  to rb_data_typed_object_wrap(),  except it  allocates a  new data
 * region internally instead of taking an existing one.  The allocation is done
 * using ruby_calloc().  Hence it makes  no sense for `type->function.dfree` to
 * be anything other than ::RUBY_TYPED_DEFAULT_FREE.
 *
 * @param[in]  klass          Ruby level class of the returning object.
 * @param[in]  size           Requested size of memory to allocate.
 * @param[in]  type           The characteristics of the passed data.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     An allocated object that wraps a new `size` byte region.
 */
VALUE rb_data_typed_object_zalloc(VALUE klass, size_t size, const rb_data_type_t *type);

/**
 * Checks for the domestic relationship between the two.
 *
 * @param[in]  child   A data type supposed to be a child of `parent`.
 * @param[in]  parent  A data type supposed to be a parent of `child`.
 * @retval     true    `child` is a descendent of `parent`.
 * @retval     false   Otherwise.
 *
 * @internal
 *
 * You can path NULL to both arguments, don't know what that means though.
 */
int rb_typeddata_inherited_p(const rb_data_type_t *child, const rb_data_type_t *parent);

/**
 * Checks if the given object is of given kind.
 *
 * @param[in]  obj        An instance of ::RTypedData.
 * @param[in]  data_type  Expected data type of `obj`.
 * @retval     true       `obj` is of `data_type`.
 * @retval     false      Otherwise.
 */
int rb_typeddata_is_kind_of(VALUE obj, const rb_data_type_t *data_type);

/**
 * Identical to rb_typeddata_is_kind_of(), except  it raises exceptions instead
 * of returning false.
 *
 * @param[in]  obj            An instance of ::RTypedData.
 * @param[in]  data_type      Expected data type of `obj`.
 * @exception  rb_eTypeError  obj is not of `data_type`.
 * @return     Unwrapped C struct that `obj` holds.
 * @post       Upon successful return `obj`'s type is guaranteed `data_type`.
 */
void *rb_check_typeddata(VALUE obj, const rb_data_type_t *data_type);
RBIMPL_SYMBOL_EXPORT_END()

/**
 * Converts sval, a pointer to your struct, into a Ruby object.
 *
 * @param      klass          A ruby level class.
 * @param      data_type      The type of `sval`.
 * @param      sval           A pointer to your struct.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     A created Ruby object.
 */
#define TypedData_Wrap_Struct(klass,data_type,sval)\
  rb_data_typed_object_wrap((klass),(sval),(data_type))

/**
 * @private
 *
 * This is  an implementation  detail of #TypedData_Make_Struct.   People don't
 * use it directly.
 *
 * @param  result     Variable name of created Ruby object.
 * @param  klass      Ruby level class of the object.
 * @param  type       Type name of the C struct.
 * @param  size       Size of the C struct.
 * @param  data_type  The data type describing `type`.
 * @param  sval       Variable name of created C struct.
 */
#define TypedData_Make_Struct0(result, klass, type, size, data_type, sval) \
    VALUE result = rb_data_typed_object_zalloc(klass, size, data_type);    \
    (sval) = RBIMPL_CAST((type *)RTYPEDDATA_DATA(result));                  \
    RBIMPL_CAST(/*suppress unused variable warnings*/(void)(sval))

/**
 * Identical to #TypedData_Wrap_Struct,  except it allocates a  new data region
 * internally instead of taking an existing  one.  The allocation is done using
 * ruby_calloc().  Hence  it makes no sense  for `data_type->function.dfree` to
 * be anything other than ::RUBY_TYPED_DEFAULT_FREE.
 *
 * @param      klass          Ruby level class of the object.
 * @param      type           Type name of the C struct.
 * @param      data_type      The data type describing `type`.
 * @param      sval           Variable name of created C struct.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     A created Ruby object.
 */
#ifdef HAVE_STMT_AND_DECL_IN_EXPR
#define TypedData_Make_Struct(klass, type, data_type, sval) \
    RB_GNUC_EXTENSION({         \
        TypedData_Make_Struct0( \
            data_struct_obj,    \
            klass,              \
            type,               \
            sizeof(type),       \
            data_type,          \
            sval);              \
        data_struct_obj;        \
    })
#else
#define TypedData_Make_Struct(klass, type, data_type, sval) \
    rb_data_typed_object_make(        \
        (klass),                      \
        (data_type),                  \
        RBIMPL_CAST((void **)&(sval)), \
        sizeof(type))
#endif

/**
 * Obtains a C struct from inside of a wrapper Ruby object.
 *
 * @param      obj            An instance of ::RTypedData.
 * @param      type           Type name of the C struct.
 * @param      data_type      The data type describing `type`.
 * @param      sval           Variable name of obtained C struct.
 * @exception  rb_eTypeError  `obj` is not a kind of `data_type`.
 * @return     Unwrapped C struct that `obj` holds.
 */
#define TypedData_Get_Struct(obj,type,data_type,sval) \
    ((sval) = RBIMPL_CAST((type *)rb_check_typeddata((obj), (data_type))))

RBIMPL_ATTR_PURE()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * @private
 *
 * This  is an  implementation detail  of  Check_Type().  People  don't use  it
 * directly.
 *
 * @param[in]  obj    Object in question
 * @retval     true   `obj` is an instance of ::RTypedData.
 * @retval     false  `obj` is an instance of ::RData.
 * @pre        `obj` must be a Ruby object of ::RUBY_T_DATA.
 */
static inline bool
rbimpl_rtypeddata_p(VALUE obj)
{
    return RTYPEDDATA(obj)->typed_flag == 1;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Checks whether the passed object is ::RTypedData or ::RData.
 *
 * @param[in]  obj    Object in question
 * @retval     true   `obj` is an instance of ::RTypedData.
 * @retval     false  `obj` is an instance of ::RData.
 * @pre        `obj` must be a Ruby object of ::RUBY_T_DATA.
 */
static inline bool
RTYPEDDATA_P(VALUE obj)
{
#if RUBY_DEBUG
    if (RB_UNLIKELY(! RB_TYPE_P(obj, RUBY_T_DATA))) {
        Check_Type(obj, RUBY_T_DATA);
        RBIMPL_UNREACHABLE_RETURN(false);
    }
#endif

    return rbimpl_rtypeddata_p(obj);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/* :TODO: can this function be __attribute__((returns_nonnull)) or not? */
/**
 * Queries for the type of given object.
 *
 * @param[in]  obj    Object in question
 * @return     Data type struct that corresponds to `obj`.
 * @pre        `obj` must be an instance of ::RTypedData.
 */
static inline const struct rb_data_type_struct *
RTYPEDDATA_TYPE(VALUE obj)
{
#if RUBY_DEBUG
    if (RB_UNLIKELY(! RTYPEDDATA_P(obj))) {
        rb_unexpected_type(obj, RUBY_T_DATA);
        RBIMPL_UNREACHABLE_RETURN(NULL);
    }
#endif

    return RTYPEDDATA(obj)->type;
}

/**
 * While  we don't  stop  you from  using  this  function, it  seems  to be  an
 * implementation  detail of  #TypedData_Make_Struct, which  is preferred  over
 * this one.
 *
 * @param[in]  klass      Ruby level class of the returning object.
 * @param[in]  type       The data type
 * @param[out] datap      Return pointer.
 * @param[in]  size       Size of the C struct.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     A created Ruby object.
 * @post       `*datap` points to the C struct wrapped by the returned object.
 */
static inline VALUE
rb_data_typed_object_make(VALUE klass, const rb_data_type_t *type, void **datap, size_t size)
{
    TypedData_Make_Struct0(result, klass, void, size, type, *datap);
    return result;
}

RBIMPL_ATTR_DEPRECATED(("by: rb_data_typed_object_wrap"))
/** @deprecated  This function was renamed to rb_data_typed_object_wrap(). */
static inline VALUE
rb_data_typed_object_alloc(VALUE klass, void *datap, const rb_data_type_t *type)
{
    return rb_data_typed_object_wrap(klass, datap, type);
}

#endif /* RBIMPL_RTYPEDDATA_H */
