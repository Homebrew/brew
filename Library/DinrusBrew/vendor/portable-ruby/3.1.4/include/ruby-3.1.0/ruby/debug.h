#ifndef RB_DEBUG_H                                   /*-*-C++-*-vi:se ft=cpp:*/
#define RB_DEBUG_H 1
/**
 * @file
 * @author     $Author: ko1 $
 * @date       Tue Nov 20 20:35:08 2012
 * @copyright  Copyright (C) 2012 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/returns_nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/event.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* Note: This file contains experimental APIs. */
/* APIs can be replaced at Ruby 2.0.1 or later */

/**
 * @name Frame-profiling APIs
 *
 * @{
 */

RBIMPL_ATTR_NONNULL((3))
/**
 * Queries mysterious "frame"s of the given range.
 *
 * The returned values are opaque backtrace  pointers, which you are allowed to
 * issue a very  limited set of operations listed below.   Don't call arbitrary
 * ruby methods.
 *
 * @param[in]   start  Start position (0 means the topmost).
 * @param[in]   limit  Number objects of `buff`.
 * @param[out]  buff   Return buffer.
 * @param[out]  lines  Return buffer.
 * @return      Number of objects filled into `buff`.
 * @post        `buff` is filled with backtrace pointers.
 * @post        `lines` is filled with `__LINE__` of each backtraces.
 *
 * @internal
 *
 * @shyouhei  doesn't  like  this  abuse  of  ::VALUE.   It  should  have  been
 * `const struct rb_callable_method_entry_struct *`.
 */
int rb_profile_frames(int start, int limit, VALUE *buff, int *lines);

/**
 * Queries the path of the passed backtrace.
 *
 * @param[in]  frame      What rb_profile_frames() returned.
 * @retval     RUBY_Qnil  The frame is implemented in C etc.
 * @retval     otherwise  Where `frame` is running.
 */
VALUE rb_profile_frame_path(VALUE frame);

/**
 * Identical  to  rb_profile_frame_path(),  except   it  tries  to  expand  the
 * returning  path.   In case  the  path  is  `require`-d from  something  else
 * rb_profile_frame_path() can return relative paths.   This one tries to avoid
 * that.
 *
 * @param[in]  frame      What rb_profile_frames() returned.
 * @retval     "<cfunc>"  The frame is in C.
 * @retval     RUBY_Qnil  Can't infer real path (inside of `eval` etc.).
 * @retval     otherwise  Where `frame` is running.
 */
VALUE rb_profile_frame_absolute_path(VALUE frame);

/**
 * Queries human-readable "label" string.  This is `"<main>"` for the toplevel,
 * `"<compiled>"` for evaluated  ones, method name for methods,  class name for
 * classes.
 *
 * @param[in]  frame         What rb_profile_frames() returned.
 * @retval     RUBY_Qnil     Can't infer the label (C etc.).
 * @retval     "<main>"      The frame is global toplevel.
 * @retval     "<compiled>"  The frame is dynamic.
 * @retval     otherwise     Label of the frame.
 */
VALUE rb_profile_frame_label(VALUE frame);

/**
 * Identical  to rb_profile_frame_label(),  except  it does  not "qualify"  the
 * result.  Consider the following backtrace:
 *
 * ```ruby
 * def bar
 *   caller_locations
 * end
 *
 * def foo
 *   [1].map { bar }.first
 * end
 *
 * obj = foo.first
 * obj.label      # => "block in foo"
 * obj.base_label # => "foo"
 * ```
 *
 * @param[in]  frame         What rb_profile_frames() returned.
 * @retval     RUBY_Qnil     Can't infer the label (C etc.).
 * @retval     "<main>"      The frame is global toplevel.
 * @retval     "<compiled>"  The frame is dynamic.
 * @retval     otherwise     Base label of the frame.
 */
VALUE rb_profile_frame_base_label(VALUE frame);

/**
 * Identical to rb_profile_frame_label(), except it returns a qualified result.
 *
 * @param[in]  frame         What rb_profile_frames() returned.
 * @retval     RUBY_Qnil     Can't infer the label (C etc.).
 * @retval     "<main>"      The frame is global toplevel.
 * @retval     "<compiled>"  The frame is dynamic.
 * @retval     otherwise     Qualified label of the frame.
 *
 * @internal
 *
 * As  of writing  there is  no way  to obtain  this return  value from  a Ruby
 * script.  This may change  in future (it took 8 years  and still no progress,
 * though).
 */
VALUE rb_profile_frame_full_label(VALUE frame);

/**
 * Queries the first  line of the method  of the passed frame  pointer.  Can be
 * handy when for instance a debugger want to display the frame in question.
 *
 * @param[in]  frame      What rb_profile_frames() returned.
 * @retval     RUBY_Qnil  Can't infer the line (C etc.).
 * @retval     otherwise  Line number of the method in question.
 */
VALUE rb_profile_frame_first_lineno(VALUE frame);

/**
 * Queries the class path of the method that the passed frame represents.
 *
 * @param[in]  frame      What rb_profile_frames() returned.
 * @retval     RUBY_Qnil  Can't infer the class (global toplevel etc.).
 * @retval     otherwise  Class path as in rb_class_path().
 */
VALUE rb_profile_frame_classpath(VALUE frame);

/**
 * Queries if the method of the passed frame is a singleton class.
 *
 * @param[in]  frame        What rb_profile_frames() returned.
 * @retval     RUBY_Qtrue   It is a singleton method.
 * @retval     RUBY_Qfalse  Otherwise (normal method/non-method).
 */
VALUE rb_profile_frame_singleton_method_p(VALUE frame);

/**
 * Queries the name of the method of the passed frame.
 *
 * @param[in]  frame      What rb_profile_frames() returned.
 * @retval     RUBY_Qnil  The frame in question is not a method.
 * @retval     otherwise  Name of the method of the frame.
 */
VALUE rb_profile_frame_method_name(VALUE frame);

/**
 * Identical  to  rb_profile_frame_method_name(),  except  it  "qualifies"  the
 * return value with its defining class.
 *
 * @param[in]  frame      What rb_profile_frames() returned.
 * @retval     RUBY_Qnil  The frame in question is not a method.
 * @retval     otherwise  Qualified name of the method of the frame.
 */
VALUE rb_profile_frame_qualified_method_name(VALUE frame);

/** @} */

/**
 * @name Debug inspector APIs
 *
 * @{
 */

/** Opaque struct representing a debug inspector. */
typedef struct rb_debug_inspector_struct rb_debug_inspector_t;

/**
 * Type  of   the  callback   function  passed   to  rb_debug_inspector_open().
 * Inspection  shall happen  only inside  of  them.  The  passed pointers  gets
 * invalidated once after the callback returns.
 *
 * @param[in]      dc    A debug context.
 * @param[in,out]  data  What was passed to rb_debug_inspector_open().
 * @return         What would be the return value of rb_debug_inspector_open().
 */
typedef VALUE (*rb_debug_inspector_func_t)(const rb_debug_inspector_t *dc, void *data);

/**
 * Prepares, executes, then cleans up a debug session.
 *
 * @param[in]      func  A callback to run inside of a debug session.
 * @param[in,out]  data  Passed as-is to `func`.
 * @return         What was returned from `func`.
 */
VALUE rb_debug_inspector_open(rb_debug_inspector_func_t func, void *data);

/**
 * Queries the current receiver of the passed context's upper frame.
 *
 * @param[in]  dc           A debug context.
 * @param[in]  index        Index of the frame from top to bottom.
 * @exception  rb_eArgError `index` out of range.
 * @return     The current receiver at `index`-th frame.
 */
VALUE rb_debug_inspector_frame_self_get(const rb_debug_inspector_t *dc, long index);

/**
 * Queries the current class of the passed context's upper frame.
 *
 * @param[in]  dc           A debug context.
 * @param[in]  index        Index of the frame from top to bottom.
 * @exception  rb_eArgError `index` out of range.
 * @return     The current class at `index`-th frame.
 */
VALUE rb_debug_inspector_frame_class_get(const rb_debug_inspector_t *dc, long index);

/**
 * Queries the binding of the passed context's upper frame.
 *
 * @param[in]  dc           A debug context.
 * @param[in]  index        Index of the frame from top to bottom.
 * @exception  rb_eArgError `index` out of range.
 * @return     The binding at `index`-th frame.
 */
VALUE rb_debug_inspector_frame_binding_get(const rb_debug_inspector_t *dc, long index);

/**
 * Queries the instruction sequence of the passed context's upper frame.
 *
 * @param[in]  dc           A debug context.
 * @param[in]  index        Index of the frame from top to bottom.
 * @exception  rb_eArgError `index` out of range.
 * @retval     RUBY_Qnil    `index`-th frame is not in Ruby (C etc.).
 * @retval     otherwise    An instance  of `RubyVM::InstructionSequence` which
 *                          represents the  instruction sequence  at `index`-th
 *                          frame.
 */
VALUE rb_debug_inspector_frame_iseq_get(const rb_debug_inspector_t *dc, long index);

/**
 * Queries  the backtrace  object  of the  context.   This is  as  if you  call
 * `caller_locations` at the point of debugger.
 *
 * @param[in]  dc  A debug context.
 * @return     An array  of `Thread::Backtrace::Location` which  represents the
 *             current point of execution at `dc`.

 */
VALUE rb_debug_inspector_backtrace_locations(const rb_debug_inspector_t *dc);

/** @} */

/**
 * @name Old style set_trace_func APIs
 *
 * @{
 */

/* duplicated def of include/ruby/ruby.h */
#include "ruby/internal/event.h"

/**
 * Identical to  rb_remove_event_hook(), except it additionally  takes the data
 * argument.  This extra  argument is the same as  that of rb_add_event_hook(),
 * and this function removes the hook which matches both arguments at once.
 *
 * @param[in]  func  A callback.
 * @param[in]  data  What to be passed to `func`.
 * @return     Number of deleted event hooks.
 * @note       As  multiple  events can  share  the  same  `func` it  is  quite
 *             possible for the return value to become more than one.
 */
int rb_remove_event_hook_with_data(rb_event_hook_func_t func, VALUE data);

/**
 * Identical to rb_add_event_hook(), except its effect is limited to the passed
 * thread.  Other threads are not affected by this.
 *
 * @param[in]  thval          An instance of ::rb_cThread.
 * @param[in]  func           A callback.
 * @param[in]  events         A set of events that `func` should run.
 * @param[in]  data           Passed as-is to `func`.
 * @exception  rb_eTypeError  `thval` is not a thread.
 */
void rb_thread_add_event_hook(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data);

/**
 * Identical to  rb_remove_event_hook(), except it additionally  takes a thread
 * argument.     This   extra    argument   is    the   same    as   that    of
 * rb_thread_add_event_hook(), and this function removes the hook which matches
 * both arguments at once.
 *
 * @param[in]  thval          An instance of ::rb_cThread.
 * @param[in]  func           A callback.
 * @exception  rb_eTypeError  `thval` is not a thread.
 * @return     Number of deleted event hooks.
 * @note       As  multiple  events can  share  the  same  `func` it  is  quite
 *             possible for the return value to become more than one.
 */
int rb_thread_remove_event_hook(VALUE thval, rb_event_hook_func_t func);

/**
 * Identical to rb_thread_remove_event_hook(), except it additionally takes the
 * data  argument.    It  can  also   be  seen   as  a  routine   identical  to
 * rb_remove_event_hook_with_data(), except  it additionally takes  the thread.
 * This function deletes hooks that satisfy all three criteria.
 *
 * @param[in]  thval          An instance of ::rb_cThread.
 * @param[in]  func           A callback.
 * @param[in]  data           What to be passed to `func`.
 * @exception  rb_eTypeError  `thval` is not a thread.
 * @return     Number of deleted event hooks.
 * @note       As  multiple  events can  share  the  same  `func` it  is  quite
 *             possible for the return value to become more than one.
 */
int rb_thread_remove_event_hook_with_data(VALUE thval, rb_event_hook_func_t func, VALUE data);

/** @} */

/**
 * @name TracePoint APIs
 *
 * @{
 */

/**
 * Creates a  tracepoint by  registering a  callback function  for one  or more
 * tracepoint   events.  Once   the  tracepoint   is  created,   you  can   use
 * rb_tracepoint_enable to enable the tracepoint.
 *
 * @param[in]      target_thread_not_supported_yet  Meant   for   picking   the
 *                         thread  in which  the tracepoint  is to  be created.
 *                         However,   current    implementation   ignore   this
 *                         parameter,  tracepoint is  created for  all threads.
 *                         Simply specify Qnil.
 * @param[in]      events  Event(s) to listen to.
 * @param[in]      func    A callback function.
 * @param[in,out]  data    Void  pointer that  will be  passed to  the callback
 *                         function.
 *
 * When the callback function is called, it will be passed 2 parameters:
 *   1. `VALUE  tpval` -  the TracePoint  object from which  trace args  can be
 *      extracted.
 *   1. `void  *data` -  A void  pointer which  helps to  share scope  with the
 *      callback function.
 *
 * It is important to note that you cannot register callbacks for normal events
 * and internal events simultaneously because  they are different purpose.  You
 * can use  any Ruby APIs  (calling methods and so  on) on normal  event hooks.
 * However, in  internal events,  you can  not use any  Ruby APIs  (even object
 * creations).   This is  why we  can't specify  internal events  by TracePoint
 * directly.  Limitations are MRI version specific.
 *
 * Example:
 *
 * ```CXX
 * rb_tracepoint_new(
 *     Qnil,
 *     RUBY_INTERNAL_EVENT_NEWOBJ | RUBY_INTERNAL_EVENT_FREEOBJ,
 *     obj_event_i,
 *     data);
 * ```
 *
 * In this  example, a callback  function `obj_event_i` will be  registered for
 * internal           events          #RUBY_INTERNAL_EVENT_NEWOBJ           and
 * #RUBY_INTERNAL_EVENT_FREEOBJ.
 */
VALUE rb_tracepoint_new(VALUE target_thread_not_supported_yet, rb_event_flag_t events, void (*func)(VALUE, void *), void *data);

/**
 * Starts (enables) trace(s) defined by the passed object.  A TracePoint object
 * does not immediately  take effect on creation.  You have  to explicitly call
 * this API.
 *
 * @param[in]  tpval         An instance of TracePoint.
 * @exception  rb_eArgError  A trace is already running.
 * @return     Undefined value.  Forget this.  It should have returned `void`.
 * @post       Trace(s) defined by `tpval` start.
 */
VALUE rb_tracepoint_enable(VALUE tpval);

/**
 * Stops (disables) an already running instance of TracePoint.
 *
 * @param[in]  tpval  An instance of TracePoint.
 * @return     Undefined value.  Forget this.  It should have returned `void`.
 * @post       Trace(s) defined by `tpval` stop.
 */
VALUE rb_tracepoint_disable(VALUE tpval);

/**
 * Queries if the passed TracePoint is up and running.
 *
 * @param[in]  tpval        An instance of TracePoint.
 * @retval     RUBY_Qtrue   It is.
 * @retval     RUBY_Qfalse  It isn't.
 */
VALUE rb_tracepoint_enabled_p(VALUE tpval);

/**
 * Type  that  represents  a  specific  trace  event.   Roughly  resembles  the
 * tracepoint object that is passed to the block of `TracePoint.new`:
 *
 * ```ruby
 * TracePoint.new(*events) do |obj|
 *   ...                    # ^^^^^  Resembles this object.
 * end
 * ```
 */
typedef struct rb_trace_arg_struct rb_trace_arg_t;

RBIMPL_ATTR_RETURNS_NONNULL()
/**
 * Queries the current event of the passed tracepoint.
 *
 * @param[in]  tpval             An instance of TracePoint.
 * @exception  rb_eRuntimeError  `tpval` is disabled.
 * @return     The current event.
 *
 * @internal
 *
 * `tpval` is  a fake.  There is  only one instance of  ::rb_trace_arg_t at one
 * time.  This function just returns that global variable.
 */
rb_trace_arg_t *rb_tracearg_from_tracepoint(VALUE tpval);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the event of the passed trace.
 *
 * @param[in]  trace_arg  A trace instance.
 * @return     Its event.
 */
rb_event_flag_t rb_tracearg_event_flag(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to  rb_tracearg_event_flag(), except  it returns  the name  of the
 * event in Ruby's symbol.
 *
 * @param[in]  trace_arg  A trace instance.
 * @return     Its event, in Ruby level Symbol object.
 */
VALUE rb_tracearg_event(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the line of the point where the trace is at.
 *
 * @param[in]  trace_arg  A trace instance.
 * @retval     0          The trace is not at Ruby frame.
 * @return     otherwise  Its line number.
 */
VALUE rb_tracearg_lineno(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the file name of the point where the trace is at.
 *
 * @param[in]  trace_arg  A trace instance.
 * @retval     RUBY_Qnil  The trace is not at Ruby frame.
 * @retval     otherwise  Its path.
 */
VALUE rb_tracearg_path(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the method name of the point where the trace is at.
 *
 * @param[in]  trace_arg  A trace instance.
 * @retval     RUBY_Qnil  There is no method.
 * @retval     otherwise  Its method name, in Ruby level Symbol.
 */
VALUE rb_tracearg_method_id(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical  to  rb_tracearg_method_id(), except  it  returns  callee id  like
 * rb_frame_callee().
 *
 * @param[in]  trace_arg  A trace instance.
 * @retval     RUBY_Qnil  There is no method.
 * @retval     otherwise  Its method name, in Ruby level Symbol.
 */
VALUE rb_tracearg_callee_id(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the class that defines the method that the passed trace is at.  This
 * can be different from the class of rb_tracearg_self()'s return value because
 * of inheritance(s).
 *
 * @param[in]  trace_arg  A trace instance.
 * @retval     RUBY_Qnil  There is no method.
 * @retval     otherwise  Its method's class.
 */
VALUE rb_tracearg_defined_class(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Creates a binding object of the point where the trace is at.
 *
 * @param[in]  trace_arg  A trace instance.
 * @retval     RUBY_Qnil  The point has no binding.
 * @retval     otherwise  Its binding.
 *
 * @internal
 *
 * @shyouhei  has  no  idea  on  which situation  shall  this  function  return
 * ::RUBY_Qnil.
 */
VALUE rb_tracearg_binding(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the receiver of the point trace is at.
 *
 * @param[in]  trace_arg  A trace instance.
 * @return     Its receiver.
 */
VALUE rb_tracearg_self(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the return value that the trace represents.
 *
 * @param[in]  trace_arg         A trace instance.
 * @exception  rb_eRuntimeError  The tracing event is not return-related.
 * @return     The return value.
 */
VALUE rb_tracearg_return_value(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the raised exception that the trace represents.
 *
 * @param[in]  trace_arg         A trace instance.
 * @exception  rb_eRuntimeError  The tracing event is not exception-related.
 * @return     The raised exception.
 */
VALUE rb_tracearg_raised_exception(rb_trace_arg_t *trace_arg);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries the allocated/deallocated object that the trace represents.
 *
 * @param[in]  trace_arg         A trace instance.
 * @exception  rb_eRuntimeError  The tracing event is not GC-related.
 * @return     The allocated/deallocated object.
 */
VALUE rb_tracearg_object(rb_trace_arg_t *trace_arg);


/** @} */

/**
 * @name Postponed Job API
 *
 * @{
 */

/*
 * Postponed Job API
 * rb_postponed_job_register and rb_postponed_job_register_one are
 * async-signal-safe and used via SIGPROF by the "stackprof" RubyGem
 */

/**
 * Type of postponed jobs.
 *
 * @param[in,out]  arg What was passed to rb_postponed_job_register().
 */
typedef void (*rb_postponed_job_func_t)(void *arg);

/**
 * Registers a postponed job.
 *
 * There  are situations  when running  a ruby  program is  not possible.   For
 * instance when  a program is in  a signal handler; for  another instance when
 * the GC  is busy.   On such situations  however, there might  be needs  to do
 * something.  We cannot but defer such operations until we are 100% sure it is
 * safe  to execute  them.   This  mechanism is  called  postponed jobs.   This
 * function  registers a  new one.   The registered  job would  eventually gets
 * executed.
 *
 * @param[in]      flags      (Unused) reserved for future extensions.
 * @param[in]      func       Job body.
 * @param[in,out]  data       Passed as-is to `func`.
 * @retval         0          Postponed job buffer is full.  Failed.
 * @retval         otherwise  Opaque return value.
 * @post           The passed job is postponed.
 */
int rb_postponed_job_register(unsigned int flags, rb_postponed_job_func_t func, void *data);

/**
 * Identical to rb_postponed_job_register_one(),  except it additionally checks
 * for  duplicated registration.   In case  the passed  job is  already in  the
 * postponed job buffer this function does nothing.
 *
 * @param[in]      flags      (Unused) reserved for future extensions.
 * @param[in]      func       Job body.
 * @param[in,out]  data       Passed as-is to `func`.
 * @retval         0          Postponed job buffer is full.  Failed.
 * @retval         otherwise  Opaque return value.
 */
int rb_postponed_job_register_one(unsigned int flags, rb_postponed_job_func_t func, void *data);

/** @} */

/**
 * @cond INTERNAL_MACRO
 *
 * Anything  after this  are  intentionally left  undocumented,  to honour  the
 * comment below.
 */

/* undocumented advanced tracing APIs */

typedef enum {
    RUBY_EVENT_HOOK_FLAG_SAFE    = 0x01,
    RUBY_EVENT_HOOK_FLAG_DELETED = 0x02,
    RUBY_EVENT_HOOK_FLAG_RAW_ARG = 0x04
} rb_event_hook_flag_t;

void rb_add_event_hook2(rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flag);
void rb_thread_add_event_hook2(VALUE thval, rb_event_hook_func_t func, rb_event_flag_t events, VALUE data, rb_event_hook_flag_t hook_flag);

/** @endcond */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_DEBUG_H */
