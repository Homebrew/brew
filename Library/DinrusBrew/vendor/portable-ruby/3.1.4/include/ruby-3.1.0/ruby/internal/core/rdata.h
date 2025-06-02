#ifndef RBIMPL_RDATA_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RDATA_H
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
 * @brief      Defines struct ::RData.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/warning.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/defines.h"

/** @cond INTERNAL_MACRO */
#ifdef RUBY_UNTYPED_DATA_WARNING
# /* Take that. */
#elif defined(RUBY_EXPORT)
# define RUBY_UNTYPED_DATA_WARNING 1
#else
# define RUBY_UNTYPED_DATA_WARNING 0
#endif

#define RBIMPL_DATA_FUNC(f) RBIMPL_CAST((void (*)(void *))(f))
#define RBIMPL_ATTRSET_UNTYPED_DATA_FUNC() \
    RBIMPL_ATTR_WARNING(("untyped Data is unsafe; use TypedData instead")) \
    RBIMPL_ATTR_DEPRECATED(("by TypedData"))

#define RBIMPL_MACRO_SELECT(x, y) x ## y
#define RUBY_MACRO_SELECT(x, y)   RBIMPL_MACRO_SELECT(x, y)
/** @endcond */

/**
 * Convenient casting macro.
 *
 * @param   obj  An object, which is in fact an ::RData.
 * @return  The passed object casted to ::RData.
 */
#define RDATA(obj)                RBIMPL_CAST((struct RData *)(obj))

/**
 * Convenient getter macro.
 *
 * @param   obj  An object, which is in fact an ::RData.
 * @return  The passed object's ::RData::data field.
 */
#define DATA_PTR(obj)             RDATA(obj)->data

/**
 * This is a value you can set  to ::RData::dfree.  Setting this means the data
 * was allocated using ::ruby_xmalloc() (or variants), and shall be freed using
 * ::ruby_xfree().
 *
 * @warning  Do not  use this  if you  want to use  system malloc,  because the
 *           system  and  Ruby  might  or  might  not  share  the  same  malloc
 *           implementation.
 */
#define RUBY_DEFAULT_FREE         RBIMPL_DATA_FUNC(-1)

/**
 * This is a value you can set  to ::RData::dfree.  Setting this means the data
 * is managed by  someone else, like, statically allocated.  Of  course you are
 * on your own then.
 */
#define RUBY_NEVER_FREE           RBIMPL_DATA_FUNC(0)

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define RUBY_UNTYPED_DATA_FUNC(f) f RBIMPL_ATTRSET_UNTYPED_DATA_FUNC()

/*
#define RUBY_DATA_FUNC(func) ((void (*)(void*))(func))
*/

/**
 * This is  the type of callbacks  registered to ::RData.  The  argument is the
 * `data` field.
 */
typedef void (*RUBY_DATA_FUNC)(void*);

/**
 * @deprecated
 *
 * Old  "untyped"  user  data.   It  has  roughly  the  same  usage  as  struct
 * ::RTypedData, but lacked several features such as support for compaction GC.
 * Use of this struct is not recommended  any longer.  If it is dead necessary,
 * please inform the core devs about your usage.
 *
 * @internal
 *
 * @shyouhei tried to add RBIMPL_ATTR_DEPRECATED for this type but that yielded
 * too many warnings  in the core.  Maybe  we want to retry  later...  Just add
 * deprecated document for now.
 */
struct RData {

    /** Basic part, including flags and class. */
    struct RBasic basic;

    /**
     * This function is called when the object is experiencing GC marks.  If it
     * contains references to  other Ruby objects, you need to  mark them also.
     * Otherwise GC will smash your data.
     *
     * @see      rb_gc_mark()
     * @warning  This  is  called  during  GC  runs.   Object  allocations  are
     *           impossible at that moment (that is why GC runs).
     */
    RUBY_DATA_FUNC dmark;

    /**
     * This function is called when the object  is no longer used.  You need to
     * do whatever necessary to avoid memory leaks.
     *
     * @warning  This  is  called  during  GC  runs.   Object  allocations  are
     *           impossible at that moment (that is why GC runs).
     */
    RUBY_DATA_FUNC dfree;

    /** Pointer to the actual C level struct that you want to wrap. */
    void *data;
};

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * This is the primitive way to wrap an existing C struct into ::RData.
 *
 * @param[in]  klass          Ruby level class of the returning object.
 * @param[in]  datap          Pointer to the target C struct.
 * @param[in]  dmark          Mark function.
 * @param[in]  dfree          Free function.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     An allocated object that wraps `datap`.
 */
VALUE rb_data_object_wrap(VALUE klass, void *datap, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree);

/**
 * Identical to  rb_data_object_wrap(), except it  allocates a new  data region
 * internally instead of taking an existing  one.  The allocation is done using
 * ruby_calloc().   Hence  it  makes  no  sense to  pass  anything  other  than
 * ::RUBY_DEFAULT_FREE to the last argument.
 *
 * @param[in]  klass          Ruby level class of the returning object.
 * @param[in]  size           Requested size of memory to allocate.
 * @param[in]  dmark          Mark function.
 * @param[in]  dfree          Free function.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     An allocated object that wraps a new `size` byte region.
 */
VALUE rb_data_object_zalloc(VALUE klass, size_t size, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree);

/**
 * @private
 * Documented in include/ruby/internal/globals.h
 */
RUBY_EXTERN VALUE rb_cObject;
RBIMPL_SYMBOL_EXPORT_END()

/**
 * Converts sval, a pointer to your struct, into a Ruby object.
 *
 * @param      klass          A ruby level class.
 * @param      mark           Mark function.
 * @param      free           Free function.
 * @param      sval           A pointer to your struct.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     A created Ruby object.
 */
#define Data_Wrap_Struct(klass, mark, free, sval) \
    rb_data_object_wrap(                          \
        (klass),                                  \
        (sval),                                   \
        RBIMPL_DATA_FUNC(mark),                    \
        RBIMPL_DATA_FUNC(free))

/**
 * @private
 *
 * This is an implementation detail  of #Data_Make_Struct.  People don't use it
 * directly.
 *
 * @param  result     Variable name of created Ruby object.
 * @param  klass      Ruby level class of the object.
 * @param  type       Type name of the C struct.
 * @param  size       Size of the C struct.
 * @param  mark       Mark function.
 * @param  free       Free function.
 * @param  sval       Variable name of created C struct.
 */
#define Data_Make_Struct0(result, klass, type, size, mark, free, sval)  \
    VALUE result = rb_data_object_zalloc(          \
        (klass),                                   \
        (size),                                    \
        RBIMPL_DATA_FUNC(mark),                     \
        RBIMPL_DATA_FUNC(free));                    \
    (sval) = RBIMPL_CAST((type *)DATA_PTR(result)); \
    RBIMPL_CAST(/*suppress unused variable warnings*/(void)(sval))

/**
 * Identical  to  #Data_Wrap_Struct, except  it  allocates  a new  data  region
 * internally instead of taking an existing  one.  The allocation is done using
 * ruby_calloc().   Hence  it  makes  no  sense to  pass  anything  other  than
 * ::RUBY_DEFAULT_FREE to the `free` argument.
 *
 * @param      klass          Ruby level class of the returning object.
 * @param      type           Type name of the C struct.
 * @param      mark           Mark function.
 * @param      free           Free function.
 * @param      sval           Variable name of created C struct.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     A created Ruby object.
 */
#ifdef HAVE_STMT_AND_DECL_IN_EXPR
#define Data_Make_Struct(klass, type, mark, free, sval) \
    RB_GNUC_EXTENSION({      \
        Data_Make_Struct0(   \
            data_struct_obj, \
            klass,           \
            type,            \
            sizeof(type),    \
            mark,            \
            free,            \
            sval);           \
        data_struct_obj;     \
    })
#else
#define Data_Make_Struct(klass, type, mark, free, sval) \
    rb_data_object_make(              \
        (klass),                      \
        RBIMPL_DATA_FUNC(mark),        \
        RBIMPL_DATA_FUNC(free),        \
        RBIMPL_CAST((void **)&(sval)), \
        sizeof(type))
#endif

/**
 * Obtains a C struct from inside of a wrapper Ruby object.
 *
 * @param      obj            An instance of ::RData.
 * @param      type           Type name of the C struct.
 * @param      sval           Variable name of obtained C struct.
 * @return     Unwrapped C struct that `obj` holds.
 */
#define Data_Get_Struct(obj, type, sval) \
    ((sval) = RBIMPL_CAST((type*)rb_data_object_get(obj)))

RBIMPL_ATTRSET_UNTYPED_DATA_FUNC()
/**
 * @private
 *
 * This is an implementation detail of rb_data_object_wrap().  People don't use
 * it directly.
 *
 * @param[in]  klass          Ruby level class of the returning object.
 * @param[in]  ptr            Pointer to the target C struct.
 * @param[in]  mark           Mark function.
 * @param[in]  free           Free function.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     An allocated object that wraps `datap`.
 */
static inline VALUE
rb_data_object_wrap_warning(VALUE klass, void *ptr, RUBY_DATA_FUNC mark, RUBY_DATA_FUNC free)
{
    return rb_data_object_wrap(klass, ptr, mark, free);
}

/**
 * @private
 *
 * This is an  implementation detail of #Data_Get_Struct.  People  don't use it
 * directly.
 *
 * @param[in]  obj  An instance of ::RData.
 * @return     Unwrapped C struct that `obj` holds.
 */
static inline void *
rb_data_object_get(VALUE obj)
{
    Check_Type(obj, RUBY_T_DATA);
    return DATA_PTR(obj);
}

RBIMPL_ATTRSET_UNTYPED_DATA_FUNC()
/**
 * @private
 *
 * This is an  implementation detail of #Data_Get_Struct.  People  don't use it
 * directly.
 *
 * @param[in]  obj  An instance of ::RData.
 * @return     Unwrapped C struct that `obj` holds.
 */
static inline void *
rb_data_object_get_warning(VALUE obj)
{
    return rb_data_object_get(obj);
}

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR_CONSTANT_P)
# define rb_data_object_wrap_warning(klass, ptr, mark, free) \
    RB_GNUC_EXTENSION(                                       \
        __builtin_choose_expr(                               \
            __builtin_constant_p(klass) && !(klass),         \
            rb_data_object_wrap(klass, ptr, mark, free),     \
            (rb_data_object_wrap_warning)(klass, ptr, mark, free)))
#endif

/**
 * This is an implementation detail  of #Data_Make_Struct.  People don't use it
 * directly.
 *
 * @param[in]  klass           Ruby level class of the returning object.
 * @param[in]  mark_func       Mark function.
 * @param[in]  free_func       Free function.
 * @param[in]  datap           Variable of created C struct.
 * @param[in]  size            Requested size of allocation.
 * @exception  rb_eTypeError  `klass` is not a class.
 * @exception  rb_eNoMemError  Out of memory.
 * @return     A created Ruby object.
 * @post       `*datap` holds the created C struct.
 */
static inline VALUE
rb_data_object_make(VALUE klass, RUBY_DATA_FUNC mark_func, RUBY_DATA_FUNC free_func, void **datap, size_t size)
{
    Data_Make_Struct0(result, klass, void, size, mark_func, free_func, *datap);
    return result;
}

RBIMPL_ATTR_DEPRECATED(("by: rb_data_object_wrap"))
/** @deprecated  This function was renamed to rb_data_object_wrap(). */
static inline VALUE
rb_data_object_alloc(VALUE klass, void *data, RUBY_DATA_FUNC dmark, RUBY_DATA_FUNC dfree)
{
    return rb_data_object_wrap(klass, data, dmark, dfree);
}

RBIMPL_ATTR_DEPRECATED(("by: rb_cObject.  Will be removed in 3.1."))
RBIMPL_ATTR_PURE()
/**
 * @private
 *
 * @deprecated  There  once was  a variable  called rb_cData,  which no  longer
 *              exists  today.  This  function is  a function  because we  want
 *              warnings for the usages.
 */
static inline VALUE
rb_cData(void)
{
    return rb_cObject;
}

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define rb_cData rb_cData()

/** @cond INTERNAL_MACRO */
#define rb_data_object_wrap_0 rb_data_object_wrap
#define rb_data_object_wrap_1 rb_data_object_wrap_warning
#define rb_data_object_wrap_2 rb_data_object_wrap_ /* Used here vvvv */
#define rb_data_object_wrap   RUBY_MACRO_SELECT(rb_data_object_wrap_2, RUBY_UNTYPED_DATA_WARNING)
#define rb_data_object_get_0  rb_data_object_get
#define rb_data_object_get_1  rb_data_object_get_warning
#define rb_data_object_get_2  rb_data_object_get_ /* Used here vvvv */
#define rb_data_object_get    RUBY_MACRO_SELECT(rb_data_object_get_2, RUBY_UNTYPED_DATA_WARNING)
#define rb_data_object_make_0 rb_data_object_make
#define rb_data_object_make_1 rb_data_object_make_warning
#define rb_data_object_make_2 rb_data_object_make_ /* Used here vvvv */
#define rb_data_object_make   RUBY_MACRO_SELECT(rb_data_object_make_2, RUBY_UNTYPED_DATA_WARNING)
/** @endcond */
#endif /* RBIMPL_RDATA_H */
