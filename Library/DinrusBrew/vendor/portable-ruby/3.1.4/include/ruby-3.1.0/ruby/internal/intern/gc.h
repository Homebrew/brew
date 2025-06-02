#ifndef RBIMPL_INTERN_GC_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_GC_H
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
 * @brief      Public APIs related to ::rb_mGC.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>                       /* size_t */
#endif

#if HAVE_SYS_TYPES_H
# include <sys/types.h>                    /* ssize_t */
#endif

#include "ruby/internal/attr/cold.h"
#include "ruby/internal/attr/noreturn.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* gc.c */

RBIMPL_ATTR_COLD()
RBIMPL_ATTR_NORETURN()
/**
 * Triggers out-of-memory error.  If  possible it raises ::rb_eNoMemError.  But
 * because  we are  running out  of  memory that  is not  always doable.   This
 * function tries hard to show something, but ultimately can die silently.
 *
 * @exception  rb_eNoMemError  Raises it if possible.
 */
void rb_memerror(void);

RBIMPL_ATTR_PURE()
/**
 * Queries if the GC is busy.
 *
 * @retval  0  It isn't.
 * @retval  1  It is.
 */
int rb_during_gc(void);

RBIMPL_ATTR_NONNULL((1))
/**
 * Marks  objects between  the two  pointers.  This  is one  of the  GC utility
 * functions    that   you    can    call   when    you    design   your    own
 * ::rb_data_type_struct::dmark.
 *
 * @pre         Continuous memory region  from `start` to `end`  shall be fully
 *              addressable.
 * @param[out]  start  Pointer to an array of objects.
 * @param[out]  end    Pointer that terminates the array of objects.
 * @post        Objects from `start` to `end`, both inclusive, are marked.
 *
 * @internal
 *
 * `end` can be NULL...  But that just results in no-op.
 */
void rb_gc_mark_locations(const VALUE *start, const VALUE *end);

/**
 * Identical to  rb_mark_hash(), except it marks  only values of the  table and
 * leave  their  associated keys  unmarked.  This  is  one  of the  GC  utility
 * functions    that   you    can    call   when    you    design   your    own
 * ::rb_data_type_struct::dmark.
 *
 * @warning    Of course it can break GC.  Leave it unused if unsure.
 * @param[in]  tbl  A table to mark.
 * @post       Values stored in `tbl` are marked.
 */
void rb_mark_tbl(struct st_table *tbl);

/**
 * Identical    to   rb_mark_tbl(),    except    it    marks   objects    using
 * rb_gc_mark_movable().  This is one of the  GC utility functions that you can
 * call when you design your own ::rb_data_type_struct::dmark.
 *
 * @warning    Of course it can break GC.  Leave it unused if unsure.
 * @param[in]  tbl  A table to mark.
 * @post       Values stored in `tbl` are marked.
 */
void rb_mark_tbl_no_pin(struct st_table *tbl);

/**
 * Identical to  rb_mark_hash(), except  it marks  only keys  of the  table and
 * leave  their associated  values unmarked.   This is  one of  the GC  utility
 * functions    that   you    can    call   when    you    design   your    own
 * ::rb_data_type_struct::dmark.
 *
 * @warning    Of course it can break GC.  Leave it unused if unsure.
 * @param[in]  tbl  A table to mark.
 * @post       Keys stored in `tbl` are marked.
 */
void rb_mark_set(struct st_table *tbl);

/**
 * Marks keys and values  associated inside of the given table.  This is one of
 * the  GC  utility functions  that  you  can call  when  you  design your  own
 * ::rb_data_type_struct::dmark.
 *
 * @param[in]  tbl  A table to mark.
 * @post       Objects stored in `tbl` are marked.
 */
void rb_mark_hash(struct st_table *tbl);

/**
 * Updates  references  inside  of  tables.   After  you  marked  values  using
 * rb_mark_tbl_no_pin(), the  objects inside  of the table  could of  course be
 * moved.  This function is to fixup  those references.  You can call this from
 * your ::rb_data_type_struct::dcompact.
 *
 * @param[out]  ptr  A table that potentially includes moved references.
 * @post        Moved references, if any, are corrected.
 */
void rb_gc_update_tbl_refs(st_table *ptr);

/**
 * Identical  to  rb_gc_mark(),  except  it   allows  the  passed  value  be  a
 * non-object.  For instance  pointers to different type of  memory regions are
 * allowed here.   Such values  are silently  ignored.  This is  one of  the GC
 * utility   functions  that   you  can   call   when  you   design  your   own
 * ::rb_data_type_struct::dmark.
 *
 * @param[out]  obj  A possible object.
 * @post        `obj` is marked, if possible.
 */
void rb_gc_mark_maybe(VALUE obj);

/**
 * Marks an object.  This is one of  the GC utility functions that you can call
 * when you design your own ::rb_data_type_struct::dmark.
 *
 * @param[out]  obj  Arbitrary Ruby object.
 * @post        `obj` is marked.
 */
void rb_gc_mark(VALUE obj);

/**
 * Maybe this  is the only  function provided for  C extensions to  control the
 * pinning of objects, so  let us describe it in detail.   These days Ruby's GC
 * is copying.  As far as an object's physical address is guaranteed unused, it
 * can move  around the object space.   Our GC engine rearranges  these objects
 * after it  reclaims unreachable objects  from our  object space, so  that the
 * space  is   compact  (improves  memory   locality).   This  is   called  the
 * "compaction" phase, and works  well most of the time... as  far as there are
 * no C  extensions.  C  extensions complicate the  scenario because  Ruby core
 * cannot detect  any use  of the  physical address  of an  object inside  of C
 * functions.  In order to prevent  memory corruptions, objects observable from
 * C extensions are "pinned"; they stick to where they are born until they die,
 * just in  case any C  extensions touch their  raw pointers.  This  variant of
 * scheme  is   called  "Mostly-Copying"  garbage  collector.    Authors  of  C
 * extensions,  however,   can  extremely   carefully  write  them   to  become
 * compaction-aware.  To do so avoid referring  to a Ruby object from inside of
 * your struct  in the  first place.   But if  that is  not possible,  use this
 * function  from your  ::rb_data_type_struct::dmark  then.   This way  objects
 * marked using it are  considered movable.  If you chose this  way you have to
 * manually fix up locations of such moved pointers using rb_gc_location().
 *
 * @see  Bartlett,  Joel  F.,  "Compacting Garbage  Collection  with  Ambiguous
 *       Roots",  ACM  SIGPLAN  Lisp  Pointers  Volume  1  Issue  6  pp.  3-12,
 *       April-May-June, 1988. https://doi.org/10.1145/1317224.1317225
 *
 * @param[in]  obj  Object that is movable.
 * @post       Values stored in `tbl` are marked.
 */
void rb_gc_mark_movable(VALUE obj);

/**
 * Finds a new "location" of an object.   An object can be moved on compaction.
 * This function projects  its new abode, or just returns  the passed object if
 * not moved.  This is  one of the GC utility functions that  you can call when
 * you design your own ::rb_data_type_struct::dcompact.
 *
 * @param[in]  obj  An object, possibly already moved to somewhere else.
 * @return     An object, which holds the current contents of former `obj`.
 */
VALUE rb_gc_location(VALUE obj);

/**
 * Asserts  that the  passed  object is  no longer  needed.   Such objects  are
 * reclaimed sooner or later so this  function is not mandatory.  But sometimes
 * you can know  from your application knowledge that an  object is surely dead
 * at some point.  Calling this as a hint can be a polite way.
 *
 * @param[out]  obj  Object, dead.
 * @pre         `obj` have never been passed to this function before.
 * @post        `obj` could be invalidated.
 * @warning     It  is a  failure  to pass  an object  multiple  times to  this
 *              function.
 * @deprecated  This is now a no-op function.
 */
RBIMPL_ATTR_DEPRECATED(("this is now a no-op function"))
void rb_gc_force_recycle(VALUE obj);

/**
 * Triggers a GC process.  This was the only  GC entry point that we had at the
 * beginning.  Over time our GC evolved.  Now what this function does is just a
 * very  simplified  variation  of  the  entire GC  algorithms.   A  series  of
 * procedures kicked by this API is called a "full" GC.
 *
 *   - It immediately scans the entire object space to sort the dead.
 *   - It immediately reclaims any single dead bodies to reuse later.
 *
 * It is worth  noting that the procedures above do  not include evaluations of
 * finalisers.  They run later.
 *
 * @internal
 *
 * Finalisers   are   deferred   until   we   can   handle   interrupts.    See
 * `rb_postponed_job_flush` in vm_trace.c.
 *
 * Of course there are  GC that are not "full".  For instance  this one and the
 * GC  which  runs when  we  are  running out  of  memory  are different.   See
 * `gc_profile_record_flag` defined in gc.c for the kinds of GC.
 *
 * In spite of the name this is not  what everything that a GC can trigger.  As
 * of writing  it seems this  function does  not trigger compaction.   But this
 * might change in future.
 */
void rb_gc(void);

/**
 * Copy&paste an object's finaliser to another.   This is one of the GC utility
 * functions  that you  can call  when you  design your  own `initialize_copy`,
 * `initialize_dup`, `initialize_clone`.
 *
 * @param[out]  dst  Destination object.
 * @param[in]   src  Source object.
 * @post        `dst` and `src` share the same finaliser.
 *
 * @internal
 *
 * But isn't it  easier for you to call super,  and let `Object#initialize_copy`
 * call this function instead?
 */
void rb_gc_copy_finalizer(VALUE dst, VALUE src);

/**
 * (Re-) enables GC.  This makes sense only after you called rb_gc_disable().
 *
 * @retval  RUBY_Qtrue   GC was disabled before.
 * @retval  RUBY_Qfalse  GC was enabled before.
 * @post    GC is enabled.
 *
 * @internal
 *
 * This is  one of  such exceptional  functions that does  not raise  both Ruby
 * exceptions and C++ exceptions.
 */
VALUE rb_gc_enable(void);

/**
 * Disables GC.   This prevents automatic GC  runs when the process  is running
 * out of memory.  Such situations shall result in rb_memerror().  However this
 * does not  prevent users from  manually invoking rb_gc().  That  should work.
 * People  abused this  by disabling  GC  at the  beginning of  an event  loop,
 * process events without GC overheads,  then manually force reclaiming garbage
 * at the bottom of the loop.  However  because our GC is now much smarter than
 * just calling rb_gc(), this technique is proven to be sub-optimal these days.
 * It  is  believed that  there  is  currently  practically  no needs  of  this
 * function.
 *
 * @retval  RUBY_Qtrue   GC was disabled before.
 * @retval  RUBY_Qfalse  GC was enabled before.
 * @post    GC is disabled.
 */
VALUE rb_gc_disable(void);

/**
 * Identical to rb_gc(), except the return value.
 *
 * @return  Always returns ::RUBY_Qnil.
 */
VALUE rb_gc_start(void);

/**
 * Assigns a finaliser for an object.  Each objects can have objects (typically
 * blocks)  that run  immediately  after  that object  dies.   They are  called
 * finalisers of an object.  This function associates a finaliser object with a
 * target object.
 *
 * @note  Note that finalisers run _after_  the object they finalise dies.  You
 *        cannot for instance call its methods.
 * @note  If  your finaliser  references the  object it  finalises that  object
 *        loses any chance to become  a garbage; effectively leaks memory until
 *        the end of the process.
 *
 * @param[in]  obj               Target to finalise.
 * @param[in]  block             Something `call`able.
 * @exception  rb_eRuntimeError  Somehow `obj` cannot have finalisers.
 * @exception  rb_eFrozenError   `obj` is frozen.
 * @exception  rb_eArgError      `block` doesn't respond to `call`.
 * @return     The passed `block`.
 * @post       `block` runs after `obj` dies.
 */
VALUE rb_define_finalizer(VALUE obj, VALUE block);

/**
 * Modifies the object so  that it has no finalisers at  all.  This function is
 * mainly provided for symmetry.  No practical usages can be thought of.
 *
 * @param[out]  obj               Object to clear its finalisers.
 * @exception   rb_eFrozenError  `obj` is frozen.
 * @return      The passed `obj`.
 * @post        `obj` has no finalisers.
 * @note        There is no way to undefine  a specific part of many finalisers
 *              that `obj` could have.  All you can do is to clear them all.
 */
VALUE rb_undefine_finalizer(VALUE obj);

/**
 * Identical to rb_gc_stat(), with "count" parameter.
 *
 * @return  Lifetime total number of runs of GC.
 */
size_t rb_gc_count(void);

/**
 * Obtains various GC  related profiles.  The parameter can be  either a Symbol
 * or a  Hash.  If  a Hash is  passed, it is  filled with  everything currently
 * available.  If a Symbol is passed just that portion is returned.
 *
 * Possible  variations of  keys  you  can pass  here  change  from version  to
 * version.  You can  get the list of  known keys by passing an  empty hash and
 * let it be filled.
 *
 * @param[in,out]  key_or_buf       A Symbol, or a Hash.
 * @exception      rb_eTypeError    Neither Symbol nor Hash.
 * @exception      rb_eFrozenError  Frozen hash is passed.
 * @return         In  case a  Hash  is  passed it  returns  0.  Otherwise  the
 *                 profile value associated with the given key is returned.
 * @post           In case a Hash is passed it is filled with values.
 */
size_t rb_gc_stat(VALUE key_or_buf);

/**
 * Obtains various  info regarding the most  recent GC run.  This  includes for
 * instance the reason  of the GC.  The  parameter can be either a  Symbol or a
 * Hash.   If  a  Hash  is  passed, it  is  filled  with  everything  currently
 * available.  If a Symbol is passed just that portion is returned.
 *
 * Possible  variations of  keys  you  can pass  here  change  from version  to
 * version.  You can  get the list of  known keys by passing an  empty hash and
 * let it be filled.
 *
 * @param[in,out]  key_or_buf       A Symbol, or a Hash.
 * @exception      rb_eTypeError    Neither Symbol nor Hash.
 * @exception      rb_eFrozenError  Frozen hash is passed.
 * @return         In case  a Hash is  passed it returns that  hash.  Otherwise
 *                 the profile value associated with the given key is returned.
 * @post           In case a Hash is passed it is filled with values.
 */
VALUE rb_gc_latest_gc_info(VALUE key_or_buf);

/**
 * Informs that  there are  external memory  usages.  Our GC  runs when  we are
 * running out of memory.  The amount of memory, however, can increase/decrease
 * behind-the-scene.  For  instance DLLs can allocate  memories using `mmap(2)`
 * etc, which  are opaque to  us.  Registering such external  allocations using
 * this function enables  proper detection of how much memories  an object used
 * as a whole.  That will trigger GCs  more often than it would otherwise.  You
 * can  also  pass  negative  numbers  here, to  indicate  that  such  external
 * allocations are gone.
 *
 * @param[in]  diff  Amount of memory increased(+)/decreased(-).
 */
void rb_gc_adjust_memory_usage(ssize_t diff);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_GC_H */
