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
#define RBIMPL_ATTR_DEPRECATED_INTERNAL_ONLY() RBIMPL_ATTR_DEPRECATED(("only for internal use"))

RBIMPL_ATTR_DEPRECATED_INTERNAL_ONLY() void rb_clear_constant_cache(void);

/* from version.c */
#if defined(RUBY_SHOW_COPYRIGHT_TO_DIE) && !!(RUBY_SHOW_COPYRIGHT_TO_DIE+0)
# error RUBY_SHOW_COPYRIGHT_TO_DIE is deprecated
#endif

#endif /* RUBY_RUBY_BACKWARD_H */
