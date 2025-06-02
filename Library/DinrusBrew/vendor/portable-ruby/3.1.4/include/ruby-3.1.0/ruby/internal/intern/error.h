#ifndef RBIMPL_INTERN_ERROR_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_ERROR_H
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
 * @brief      Public APIs related to ::rb_eException.
 */
#include "ruby/internal/attr/format.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/fl_type.h"
#include "ruby/backward/2/assume.h"

/**
 * This macro is used in conjunction  with rb_check_arity().  If you pass it to
 * the function's last  (max) argument, that means the function  does not check
 * upper limit.
 */
#define UNLIMITED_ARGUMENTS     (-1)

#define rb_exc_new2             rb_exc_new_cstr  /**< @old{rb_exc_new_cstr} */
#define rb_exc_new3             rb_exc_new_str  /**< @old{rb_exc_new_str} */

/** @cond INTERNAL_MACRO */
#define rb_check_trusted        rb_check_trusted
#define rb_check_trusted_inline rb_check_trusted
#define rb_check_arity          rb_check_arity
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* error.c */

/**
 * Creates an instance of the passed exception class.
 *
 * @param[in]  etype           A subclass of ::rb_eException.
 * @param[in]  ptr             Buffer contains error message.
 * @param[in]  len             Length  of `ptr`,  in bytes,  not including  the
 *                             terminating NUL character.
 * @exception  rb_eTypeError  `etype` is not a class.
 * @exception  rb_eArgError   `len` is negative.
 * @return     An instance of `etype`.
 * @pre        At  least  `len` bytes  of  continuous  memory region  shall  be
 *             accessible via `ptr`.
 *
 * @internal
 *
 * This function works for non-exception classes  as well, as long as they take
 * one string argument.
 */
VALUE rb_exc_new(VALUE etype, const char *ptr, long len);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to rb_exc_new(), except it assumes the passed pointer is a pointer
 * to a C string.
 *
 * @param[in]  etype           A subclass of ::rb_eException.
 * @param[in]  str             A C string (becomes an error message).
 * @exception  rb_eTypeError  `etype` is not a class.
 * @return     An instance of `etype`.
 */
VALUE rb_exc_new_cstr(VALUE etype, const char *str);

/**
 * Identical to rb_exc_new_cstr(),  except it takes a Ruby's  string instead of
 * C's.
 *
 * @param[in]  etype           A subclass of ::rb_eException.
 * @param[in]  str             An instance of ::rb_cString.
 * @exception  rb_eTypeError  `etype` is not a class.
 * @return     An instance of `etype`.
 */
VALUE rb_exc_new_str(VALUE etype, VALUE str);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((1))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 2)
/**
 * Raises an instance of ::rb_eLoadError.
 *
 * @param[in]  fmt  Format specifier string compatible with rb_sprintf().
 * @exception  rb_eLoadError  Always raises this.
 * @note       It never returns.
 *
 * @internal
 *
 * Who needs this?  Except ruby itself?
 */
void rb_loaderror(const char *fmt, ...);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Identical  to rb_loaderror(),  except it  additionally takes  which file  is
 * unable to  load.  The path can  be obtained later using  `LoadError#path` of
 * the raising exception.
 *
 * @param[in]  path  What failed.
 * @param[in]  fmt   Format specifier string compatible with rb_sprintf().
 * @exception  rb_eLoadError  Always raises this.
 * @note       It never returns.
 */
void rb_loaderror_with_path(VALUE path, const char *fmt, ...);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Raises an instance of ::rb_eNameError.  The name can be obtained later using
 * `NameError#name` of the raising exception.
 *
 * @param[in]  name  What failed.
 * @param[in]  fmt   Format specifier string compatible with rb_sprintf().
 * @exception  rb_eNameError  Always raises this.
 * @note       It never returns.
 */
void rb_name_error(ID name, const char *fmt, ...);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Identical to rb_name_error(), except it takes a ::VALUE instead of ::ID.
 *
 * @param[in]  name  What failed.
 * @param[in]  fmt   Format specifier string compatible with rb_sprintf().
 * @exception  rb_eNameError  Always raises this.
 * @note       It never returns.
 */
void rb_name_error_str(VALUE name, const char *fmt, ...);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL((2))
RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 3)
/**
 * Raises an instance  of ::rb_eFrozenError.  The object can  be obtained later
 * using `FrozenError#receiver` of the raising exception.
 *
 * @param[in]  recv  What is frozen.
 * @param[in]  fmt   Format specifier string compatible with rb_sprintf().
 * @exception  rb_eFrozenError  Always raises this.
 * @note       It never returns.
 *
 * @internal
 *
 * Note however,  that it  is often  not possible to  inspect a  frozen object,
 * because the inspection itself could be forbidden by the frozen-ness.
 */
void rb_frozen_error_raise(VALUE recv, const char *fmt, ...);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL(())
/**
 * Honestly  I  don't  understand  the  name, but  it  raises  an  instance  of
 * ::rb_eArgError.
 *
 * @param[in]  str           A message.
 * @param[in]  type          Another message.
 * @exception  rb_eArgError  Always raises this.
 * @note       It never returns.
 */
void rb_invalid_str(const char *str, const char *type);

RBIMPL_ATTR_NORETURN()
RBIMPL_ATTR_NONNULL(())
/**
 * Identical  to rb_frozen_error_raise(),  except its  raising exception  has a
 * message like "can't modify frozen /what/".
 *
 * @param[in]  what             What was frozen.
 * @exception  rb_eFrozenError  Always raises this.
 * @note       It never returns.
 */
void rb_error_frozen(const char *what);

RBIMPL_ATTR_NORETURN()
/**
 * Identical  to  rb_error_frozen(),  except  it takes  arbitrary  Ruby  object
 * instead of C's string.
 *
 * @param[in]  what             What was frozen.
 * @exception  rb_eFrozenError  Always raises this.
 * @note       It never returns.
 */
void rb_error_frozen_object(VALUE what);

/**
 * @deprecated  Does nothing.  This method is deprecated and will be removed in
 *              Ruby 3.2.
 */
void rb_error_untrusted(VALUE);

/**
 * Queries  if the  passed  object is  frozen.
 *
 * @param[in]  obj  Target object to test frozen-ness.
 * @exception  rb_eFrozenError  It is frozen.
 * @post       Upon successful return it is guaranteed _not_ frozen.
 */
void rb_check_frozen(VALUE obj);

/**
 * @deprecated  Does nothing.  This method is deprecated and will be removed in
 *              Ruby 3.2.
 */
void rb_check_trusted(VALUE);

/**
 * Ensures that the passed object  can be `initialize_copy` relationship.  When
 * you implement your own one you would better call this at the right beginning
 * of your implementation.
 *
 * @param[in]  obj              Destination object.
 * @param[in]  orig             Source object.
 * @exception  rb_eFrozenError  `obj` is frozen.
 * @post       Upon successful return obj is guaranteed safe to copy orig.
 */
void rb_check_copyable(VALUE obj, VALUE orig);

RBIMPL_ATTR_NORETURN()
/**
 * @private
 *
 * This  is an  implementation detail  of  rb_scan_args().  You  don't have  to
 * bother.
 *
 * @pre        `argc` is out of range of `min`..`max`, both inclusive.
 * @param[in]  argc          Arbitrary integer.
 * @param[in]  min           Minimum allowed `argc`.
 * @param[in]  max           Maximum allowed `argc`.
 * @exception  rb_eArgError  Always.
 */
MJIT_STATIC void rb_error_arity(int argc, int min, int max);

RBIMPL_SYMBOL_EXPORT_END()

/**
 * @deprecated
 *
 * Does anyone use this?  Remain not deleted for compatibility.
 */
#define rb_check_frozen_internal(obj) do { \
        VALUE frozen_obj = (obj); \
        if (RB_UNLIKELY(RB_OBJ_FROZEN(frozen_obj))) { \
            rb_error_frozen_object(frozen_obj); \
        } \
    } while (0)

/** @alias{rb_check_frozen} */
static inline void
rb_check_frozen_inline(VALUE obj)
{
    if (RB_UNLIKELY(RB_OBJ_FROZEN(obj))) {
        rb_error_frozen_object(obj);
    }
}

/** @alias{rb_check_frozen} */
#define rb_check_frozen rb_check_frozen_inline

/**
 * Ensures that the  passed integer is in  the passed range.  When  you can use
 * rb_scan_args() that is preferred over this one (powerful, descriptive).  But
 * it can have its own application area.
 *
 * @param[in]  argc          Arbitrary integer.
 * @param[in]  min           Minimum allowed `argv`.
 * @param[in]  max           Maximum allowed `argv`, or `UNLIMITED_ARGUMENTS`.
 * @exception  rb_eArgError  `argc` out of range.
 * @return     The passed `argc`.
 * @post       Upon successful return `argc` is  in range of `min`..`max`, both
 *             inclusive.
 */
static inline int
rb_check_arity(int argc, int min, int max)
{
    if ((argc < min) || (max != UNLIMITED_ARGUMENTS && argc > max))
        rb_error_arity(argc, min, max);
    return argc;
}

#endif /* RBIMPL_INTERN_ERROR_H */
