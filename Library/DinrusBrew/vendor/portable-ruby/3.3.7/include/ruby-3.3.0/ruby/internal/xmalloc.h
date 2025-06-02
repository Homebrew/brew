#ifndef RBIMPL_XMALLOC_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_XMALLOC_H
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
 * @brief      Declares ::ruby_xmalloc().
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

#include "ruby/internal/attr/alloc_size.h"
#include "ruby/internal/attr/nodiscard.h"
#include "ruby/internal/attr/noexcept.h"
#include "ruby/internal/attr/restrict.h"
#include "ruby/internal/attr/returns_nonnull.h"
#include "ruby/internal/dllexport.h"

/**
 * @private
 * @warning  Do not touch this macro.
 * @warning  It is an implementation detail.
 * @warning  It was a failure at the first place to let you know about it.
 * @warning  The  value of  this  macro  must match  for  ruby  itself and  all
 *           extension  libraries, otherwise  serious  memory corruption  shall
 *           occur.
 */
#ifndef USE_GC_MALLOC_OBJ_INFO_DETAILS
# define USE_GC_MALLOC_OBJ_INFO_DETAILS 0
#endif

#define xmalloc   ruby_xmalloc   /**< @old{ruby_xmalloc} */
#define xmalloc2  ruby_xmalloc2  /**< @old{ruby_xmalloc2} */
#define xcalloc   ruby_xcalloc   /**< @old{ruby_xcalloc} */
#define xrealloc  ruby_xrealloc  /**< @old{ruby_xrealloc} */
#define xrealloc2 ruby_xrealloc2 /**< @old{ruby_xrealloc2} */
#define xfree     ruby_xfree     /**< @old{ruby_xfree} */

RBIMPL_SYMBOL_EXPORT_BEGIN()

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1))
/**
 * Allocates a  storage instance.  It is  largely the same as  system malloc(),
 * except:
 *
 *   - It raises Ruby exceptions instead of returning NULL, and
 *   - In case of `ENOMEM` it tries to GC to make some room.
 *
 * @param[in]  size            Requested amount of memory.
 * @exception  rb_eNoMemError  No space left for `size` bytes allocation.
 * @return     A valid pointer  to an allocated storage instance;  which has at
 *             least `size` bytes width, with appropriate alignment detected by
 *             the underlying malloc() routine.
 * @note       It doesn't return NULL.
 * @note       Unlike some malloc() implementations, it allocates something and
 *             returns a meaningful value even when `size` is equal to zero.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
void *ruby_xmalloc(size_t size)
RBIMPL_ATTR_NOEXCEPT(malloc(size))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1,2))
/**
 * Identical to ruby_xmalloc(), except it allocates `nelems` * `elemsiz` bytes.
 * This is needed  because the multiplication could integer  overflow.  On such
 * situations  Ruby does  not try  to  allocate at  all but  raises Ruby  level
 * exceptions  instead.  If  there  is  no integer  overflow  the behaviour  is
 * exactly the same as `ruby_xmalloc(nelems*elemsiz)`.
 *
 * @param[in]  nelems          Number of elements.
 * @param[in]  elemsiz         Size of an element.
 * @exception  rb_eNoMemError  No space left for allocation.
 * @exception  rb_eArgError    `nelems` * `elemsiz` would overflow.
 * @return     A valid pointer  to an allocated storage instance;  which has at
 *             least  `nelems`  *  `elemsiz`   bytes  width,  with  appropriate
 *             alignment detected by the underlying malloc() routine.
 * @note       It doesn't return NULL.
 * @note       Unlike some malloc() implementations, it allocates something and
 *             returns a  meaningful value even  when `nelems` or  `elemsiz` or
 *             both are zero.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
void *ruby_xmalloc2(size_t nelems, size_t elemsiz)
RBIMPL_ATTR_NOEXCEPT(malloc(nelems * elemsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1,2))
/**
 * Identical  to  ruby_xmalloc2(),  except  it returns  a  zero-filled  storage
 * instance.  It  can also be  seen as  a routine identical  to ruby_xmalloc(),
 * except it calls calloc() instead of malloc().
 *
 * @param[in]  nelems          Number of elements.
 * @param[in]  elemsiz         Size of an element.
 * @exception  rb_eNoMemError  No space left for allocation.
 * @exception  rb_eArgError    `nelems` * `elemsiz` would overflow.
 * @return     A valid pointer  to an allocated storage instance;  which has at
 *             least  `nelems`  *  `elemsiz`   bytes  width,  with  appropriate
 *             alignment detected by the underlying calloc() routine.
 * @post       The returned storage instance is filled with zeros.
 * @note       It doesn't return NULL.
 * @note       Unlike some calloc() implementations, it allocates something and
 *             returns a  meaningful value even  when `nelems` or  `elemsiz` or
 *             both are zero.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
void *ruby_xcalloc(size_t nelems, size_t elemsiz)
RBIMPL_ATTR_NOEXCEPT(calloc(nelems, elemsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2))
/**
 * Resize the storage instance.
 *
 * @param[in]  ptr             A valid  pointer to a storage  instance that was
 *                             previously returned from either:
 *                               - ruby_xmalloc(),
 *                               - ruby_xmalloc2(),
 *                               - ruby_xcalloc(),
 *                               - ruby_xrealloc(), or
 *                               - ruby_xrealloc2().
 * @param[in]  newsiz          Requested new amount of memory.
 * @exception  rb_eNoMemError  No space left for `newsiz` bytes allocation.
 * @return     A  valid  pointer  to   a  (possibly  newly  allocated)  storage
 *             instance;  which  has  at   least  `newsiz`  bytes  width,  with
 *             appropriate  alignment  detected  by  the  underlying  realloc()
 *             routine.
 * @pre        The passed pointer must point  to a valid live storage instance.
 *             It is a failure to pass an already freed pointer.
 * @post       In  case the  function  returns the  passed  pointer as-is,  the
 *             storage  instance that  the  pointer holds  is  either grown  or
 *             shrunken  to have  at least  `newsiz` bytes.  Otherwise a  valid
 *             pointer to a  newly allocated storage instance  is returned.  In
 *             this  case  `ptr`  is  invalidated   as  if  it  was  passed  to
 *             ruby_xfree().
 * @note       It doesn't return NULL.
 * @warning    Unlike some realloc() implementations,  passing zero to `newsiz`
 *             is not the  same as calling ruby_xfree(),  because this function
 *             never returns NULL.  Something meaningful still returns then.
 * @warning    It is  a failure not to  check the return value.   Do not assume
 *             anything on  it.  It could  be either identical to,  or distinct
 *             form the passed argument.
 * @warning    Do not  assume anything  on the alignment  of the  return value.
 *             There is  no guarantee  that it  inherits the  passed argument's
 *             one.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
void *ruby_xrealloc(void *ptr, size_t newsiz)
RBIMPL_ATTR_NOEXCEPT(realloc(ptr, newsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2,3))
/**
 * Identical to ruby_xrealloc(),  except it resizes the  given storage instance
 * to `newelems` *  `newsiz` bytes.  This is needed  because the multiplication
 * could integer overflow.   On such situations Ruby does not  try to touch the
 * contents  of  argument pointer  at  all  but  raises Ruby  level  exceptions
 * instead.  If there is no integer  overflow the behaviour is exactly the same
 * as `ruby_xrealloc(ptr,nelems*elemsiz)`.
 *
 * This  is   roughly  the  same   as  reallocarray()  function   that  OpenBSD
 * etc. provides, but also interacts with our GC.
 *
 * @param[in]  ptr             A valid  pointer to a storage  instance that was
 *                             previously returned from either:
 *                               - ruby_xmalloc(),
 *                               - ruby_xmalloc2(),
 *                               - ruby_xcalloc(),
 *                               - ruby_xrealloc(), or
 *                               - ruby_xrealloc2().
 * @param[in]  newelems        Requested new number of elements.
 * @param[in]  newsiz          Requested new size of each element.
 * @exception  rb_eNoMemError  No space left for  allocation.
 * @exception  rb_eArgError    `newelems` * `newsiz` would overflow.
 * @return     A  valid  pointer  to   a  (possibly  newly  allocated)  storage
 *             instance; which has at least  `newelems` * `newsiz` bytes width,
 *             with appropriate alignment detected  by the underlying realloc()
 *             routine.
 * @pre        The passed pointer must point  to a valid live storage instance.
 *             It is a failure to pass an already freed pointer.
 * @post       In  case the  function  returns the  passed  pointer as-is,  the
 *             storage  instance that  the  pointer holds  is  either grown  or
 *             shrunken  to   have  at  least  `newelems`   *  `newsiz`  bytes.
 *             Otherwise a valid pointer to  a newly allocated storage instance
 *             is returned.   In this case  `ptr` is  invalidated as if  it was
 *             passed to ruby_xfree().
 * @note       It doesn't return NULL.
 * @warning    Unlike some  realloc() implementations,  passing zero  to either
 *             `newelems`   or  `elemsiz`   are   not  the   same  as   calling
 *             ruby_xfree(),   because  this   function  never   returns  NULL.
 *             Something meaningful still returns then.
 * @warning    It is  a failure not to  check the return value.   Do not assume
 *             anything on  it.  It could  be either identical to,  or distinct
 *             form the passed argument.
 * @warning    Do not  assume anything  on the alignment  of the  return value.
 *             There is  no guarantee  that it  inherits the  passed argument's
 *             one.
 * @warning    The return  value shall  be invalidated  exactly once  by either
 *             ruby_xfree(),  ruby_xrealloc(), or  ruby_xrealloc2().   It is  a
 *             failure to pass it to system free(), because the system and Ruby
 *             might or might not share the same malloc() implementation.
 */
void *ruby_xrealloc2(void *ptr, size_t newelems, size_t newsiz)
RBIMPL_ATTR_NOEXCEPT(realloc(ptr, newelems * newsiz))
;

/**
 * Deallocates a storage instance.
 *
 * @param[out]  ptr  Either
 *                     - NULL, or
 *                     - a valid pointer previously returned from one of:
 *                       - ruby_xmalloc(),
 *                       - ruby_xmalloc2(),
 *                       - ruby_xcalloc(),
 *                       - ruby_xrealloc(), or
 *                       - ruby_xrealloc2().
 * @pre         The passed pointer must point to a valid live storage instance.
 *              It is a failure to pass an already freed pointer.
 * @post        The  storage  instance  pointed  by  the  passed  pointer  gets
 *              invalidated; it is no longer addressable.
 * @warning     Every single storage instance  that was previously allocated by
 *              either    ruby_xmalloc(),   ruby_xmalloc2(),    ruby_xcalloc(),
 *              ruby_xrealloc(),  or  ruby_xrealloc2()   shall  be  invalidated
 *              exactly once by  either passing it to  ruby_xfree(), or passing
 *              it to  either ruby_xrealloc(), ruby_xrealloc2() then  check the
 *              return value for invalidation.
 * @warning     Do not pass anything other  than pointers described above.  For
 *              instance pointers returned from malloc() or mmap() shall not be
 *              passed  to   this  function,  because  the   underlying  memory
 *              management mechanism could differ.
 * @warning     Do  not pass  any invalid  pointers  to this  function e.g.  by
 *              calling it twice with a same argument.
 */
void ruby_xfree(void *ptr)
RBIMPL_ATTR_NOEXCEPT(free(ptr))
;

#if USE_GC_MALLOC_OBJ_INFO_DETAILS
# define ruby_xmalloc(s1)            ruby_xmalloc_with_location(s1, __FILE__, __LINE__)
# define ruby_xmalloc2(s1, s2)       ruby_xmalloc2_with_location(s1, s2, __FILE__, __LINE__)
# define ruby_xcalloc(s1, s2)        ruby_xcalloc_with_location(s1, s2, __FILE__, __LINE__)
# define ruby_xrealloc(ptr, s1)      ruby_xrealloc_with_location(ptr, s1, __FILE__, __LINE__)
# define ruby_xrealloc2(ptr, s1, s2) ruby_xrealloc2_with_location(ptr, s1, s2, __FILE__, __LINE__)

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1))
void *ruby_xmalloc_body(size_t size)
RBIMPL_ATTR_NOEXCEPT(malloc(size))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1,2))
void *ruby_xmalloc2_body(size_t nelems, size_t elemsiz)
RBIMPL_ATTR_NOEXCEPT(malloc(nelems * elemsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1,2))
void *ruby_xcalloc_body(size_t nelems, size_t elemsiz)
RBIMPL_ATTR_NOEXCEPT(calloc(nelems, elemsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2))
void *ruby_xrealloc_body(void *ptr, size_t newsiz)
RBIMPL_ATTR_NOEXCEPT(realloc(ptr, newsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2,3))
void *ruby_xrealloc2_body(void *ptr, size_t newelems, size_t newsiz)
RBIMPL_ATTR_NOEXCEPT(realloc(ptr, newelems * newsiz))
;

RUBY_EXTERN const char *ruby_malloc_info_file;
RUBY_EXTERN int ruby_malloc_info_line;

static inline void *
ruby_xmalloc_with_location(size_t s, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xmalloc_body(s);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xmalloc2_with_location(size_t s1, size_t s2, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xmalloc2_body(s1, s2);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xcalloc_with_location(size_t s1, size_t s2, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xcalloc_body(s1, s2);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xrealloc_with_location(void *ptr, size_t s, const char *file, int line)
{
    void *rptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    rptr = ruby_xrealloc_body(ptr, s);
    ruby_malloc_info_file = NULL;
    return rptr;
}

static inline void *
ruby_xrealloc2_with_location(void *ptr, size_t s1, size_t s2, const char *file, int line)
{
    void *rptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    rptr = ruby_xrealloc2_body(ptr, s1, s2);
    ruby_malloc_info_file = NULL;
    return rptr;
}
#endif

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_XMALLOC_H */
