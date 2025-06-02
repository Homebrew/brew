#ifndef RBIMPL_EVENT_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_EVENT_H
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
 * @brief      Debugging and tracing APIs.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif

/* These macros are not enums because they are wider than int.*/

/**
 * @name Traditional set_trace_func events
 *
 * @{
 */
#define RUBY_EVENT_NONE      0x0000 /**< No events. */
#define RUBY_EVENT_LINE      0x0001 /**< Encountered a new line. */
#define RUBY_EVENT_CLASS     0x0002 /**< Encountered a new class. */
#define RUBY_EVENT_END       0x0004 /**< Encountered an end of a class clause. */
#define RUBY_EVENT_CALL      0x0008 /**< A method, written in Ruby, is called. */
#define RUBY_EVENT_RETURN    0x0010 /**< Encountered a `return` statement. */
#define RUBY_EVENT_C_CALL    0x0020 /**< A method, written in C, is called. */
#define RUBY_EVENT_C_RETURN  0x0040 /**< Return from a method, written in C. */
#define RUBY_EVENT_RAISE     0x0080 /**< Encountered a `raise` statement. */
#define RUBY_EVENT_ALL       0x00ff /**< Bitmask of traditional events. */

/** @} */

/**
 * @name TracePoint extended events
 *
 * @{
 */
#define RUBY_EVENT_B_CALL            0x0100 /**< Encountered an `yield` statement. */
#define RUBY_EVENT_B_RETURN          0x0200 /**< Encountered a `next` statement. */
#define RUBY_EVENT_THREAD_BEGIN      0x0400 /**< Encountered a new thread. */
#define RUBY_EVENT_THREAD_END        0x0800 /**< Encountered an end of a thread. */
#define RUBY_EVENT_FIBER_SWITCH      0x1000 /**< Encountered a `Fiber#yield`. */
#define RUBY_EVENT_SCRIPT_COMPILED   0x2000 /**< Encountered an `eval`. */
#define RUBY_EVENT_RESCUE            0x4000 /**< Encountered a `rescue` statement. */
#define RUBY_EVENT_TRACEPOINT_ALL    0xffff /**< Bitmask of extended events. */

/** @} */

/**
 * @name Special events
 *
 * @internal
 *
 * These bits are actually used internally.  See vm_core.h if you are curious.
 *
 * @endinternal
 *
 * @{
 */
#define RUBY_EVENT_RESERVED_FOR_INTERNAL_USE 0x030000 /**< Opaque bits. */

/** @} */

/**
 * @name Internal events
 *
 * @shyouhei's understanding  is that some  of them are visible  from extension
 * libraries because  of `ext/objspace`.   But it  seems that  doesn't describe
 * everything?  The ultimate reason why they are here remains unclear.
 *
 * @{
 */
#define RUBY_INTERNAL_EVENT_SWITCH          0x040000 /**< Thread switched. */
#define RUBY_EVENT_SWITCH                   0x040000 /**< @old{RUBY_INTERNAL_EVENT_SWITCH} */
                                         /* 0x080000 */
#define RUBY_INTERNAL_EVENT_NEWOBJ          0x100000 /**< Object allocated. */
#define RUBY_INTERNAL_EVENT_FREEOBJ         0x200000 /**< Object swept. */
#define RUBY_INTERNAL_EVENT_GC_START        0x400000 /**< GC started. */
#define RUBY_INTERNAL_EVENT_GC_END_MARK     0x800000 /**< GC ended mark phase. */
#define RUBY_INTERNAL_EVENT_GC_END_SWEEP   0x1000000 /**< GC ended sweep phase. */
#define RUBY_INTERNAL_EVENT_GC_ENTER       0x2000000 /**< `gc_enter()` is called. */
#define RUBY_INTERNAL_EVENT_GC_EXIT        0x4000000 /**< `gc_exit()` is called. */
#define RUBY_INTERNAL_EVENT_OBJSPACE_MASK  0x7f00000 /**< Bitmask of GC events. */
#define RUBY_INTERNAL_EVENT_MASK          0xffff0000 /**< Bitmask of internal events. */

/** @} */

/**
 * Represents event(s).  As the name implies events are bit flags.
 */
typedef uint32_t rb_event_flag_t;

/**
 * Type of event hooks.  When an  event happens registered functions are kicked
 * with appropriate parameters.
 *
 * @param[in]  evflag  The kind of event that happened.
 * @param[in]  data    The `data` passed to rb_add_event_hook().
 * @param[in]  self    Current receiver.
 * @param[in]  mid     Name of the current method.
 * @param[in]  klass   Current class.
 */
typedef void (*rb_event_hook_func_t)(rb_event_flag_t evflag, VALUE data, VALUE self, ID mid, VALUE klass);

/**
 * @private
 *
 * @deprecated  This macro once was a thing in the old days, but makes no sense
 *              any  longer today.   Exists  here  for backwards  compatibility
 *              only.  You can safely forget about it.
 */
#define RB_EVENT_HOOKS_HAVE_CALLBACK_DATA 1

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Registers an event hook function.
 *
 * @param[in]  func    A callback.
 * @param[in]  events  A set of events that `func` should run.
 * @param[in]  data    Passed as-is to `func`.
 */
void rb_add_event_hook(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);

/**
 * Removes the passed function from the list of event hooks.
 *
 * @param[in]  func  A callback.
 * @return     Number of deleted event hooks.
 * @note       As  multiple  events can  share  the  same  `func` it  is  quite
 *             possible for the return value to become more than one.
 *
 * @internal
 *
 * @shyouhei doesn't know if this is an  Easter egg or an official feature, but
 * you can pass 0 to the argument.  That effectively swipes everything out from
 * the hook list.
 */
int rb_remove_event_hook(rb_event_hook_func_t func);
RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_EVENT_H */
