#ifndef RUBY_RUBY_BACKWARD_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_RUBY_BACKWARD_H 1
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/value.h"
#include "ruby/internal/interpreter.h"
#include "ruby/backward/2/attributes.h"

#define RBIMPL_ATTR_DEPRECATED_SINCE(ver) RBIMPL_ATTR_DEPRECATED(("since " #ver))
#define RBIMPL_ATTR_DEPRECATED_INTERNAL(ver) RBIMPL_ATTR_DEPRECATED(("since "#ver", also internal"))

/* eval.c */
RBIMPL_ATTR_DEPRECATED_SINCE(2.2) void rb_disable_super();
RBIMPL_ATTR_DEPRECATED_SINCE(2.2) void rb_enable_super();

/* hash.c */
RBIMPL_ATTR_DEPRECATED_SINCE(2.2) void rb_hash_iter_lev();
RBIMPL_ATTR_DEPRECATED_SINCE(2.2) void rb_hash_ifnone();

/* string.c */
RBIMPL_ATTR_DEPRECATED_SINCE(2.2) void rb_str_associate();
RBIMPL_ATTR_DEPRECATED_SINCE(2.2) void rb_str_associated();

/* variable.c */
RBIMPL_ATTR_DEPRECATED_SINCE(2.5) void rb_autoload();

/* eval.c */
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.6) void rb_frozen_class_p();
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.7) void rb_exec_end_proc();

/* error.c */
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.3) void rb_compile_error();
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.3) void rb_compile_error_with_enc();
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.3) void rb_compile_error_append();

/* gc.c */
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.7) void rb_gc_call_finalizer_at_exit();

/* signal.c */
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.7) void rb_trap_exit();

/* struct.c */
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.4) void rb_struct_ptr();

/* thread.c */
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.7) void rb_clear_trace_func();

/* variable.c */
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.7) void rb_generic_ivar_table();
RBIMPL_ATTR_DEPRECATED_INTERNAL(2.6) NORETURN(VALUE rb_mod_const_missing(VALUE, VALUE));

/* from version.c */
#if defined(RUBY_SHOW_COPYRIGHT_TO_DIE) && !!(RUBY_SHOW_COPYRIGHT_TO_DIE+0)
/* for source code backward compatibility */
RBIMPL_ATTR_DEPRECATED_SINCE(2.4)
static inline int
ruby_show_copyright_to_die(int exitcode)
{
    ruby_show_copyright();
    return exitcode;
}
#define ruby_show_copyright() /* defer EXIT_SUCCESS */ \
    (exit(ruby_show_copyright_to_die(EXIT_SUCCESS)))
#endif

#endif /* RUBY_RUBY_BACKWARD_H */
