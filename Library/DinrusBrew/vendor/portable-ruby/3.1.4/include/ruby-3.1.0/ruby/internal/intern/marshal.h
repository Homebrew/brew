#ifndef RBIMPL_INTERN_MARSHAL_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_MARSHAL_H
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
 * @brief      Public APIs related to rb_mMarshal.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* marshal.c */

/**
 * Serialises the  given object and  all its  referring objects, to  write them
 * down to the passed port.
 *
 * @param[in]   obj               Target object to dump.
 * @param[out]  port              IO-like destination buffer.
 * @exception   rb_eTypeError     `obj` cannot be dumped for some reason.
 * @exception   rb_eRuntimeError  `obj` was tampered during dumping.
 * @exception   rb_eArgError      Traversal too deep.
 * @return      The passed `port` as-is.
 * @post        Serialised representation of `obj` is written to `port`.
 * @note        `port` is basically an IO but StringIO is also possible.
 */
VALUE rb_marshal_dump(VALUE obj, VALUE port);

/**
 * Deserialises  a  previous output  of  rb_marshal_dump()  into a  network  of
 * objects.
 *
 * @param[in,out]  port           Either IO or String.
 * @exception      rb_eTypeError  `port` is in unexpected type.
 * @exception      rb_eArgError   Contents of `port` is broken.
 * @return         Object(s) rebuilt using the info from `port`.
 *
 * SECURITY  CONSIDERATIONS
 * ========================
 *
 * @warning        By  design,  rb_marshal_load()  can deserialise  almost  any
 *                 class loaded into the Ruby  process.  In many cases this can
 *                 lead to remote code execution  if the Marshal data is loaded
 *                 from an untrusted source.
 * @warning        As a result, rb_marshal_load() is  not suitable as a general
 *                 purpose serialisation format and  you should never unmarshal
 *                 user supplied input or other untrusted data.
 * @warning        If  you need  to  deserialise untrusted  data,  use JSON  or
 *                 another  serialisation  format that  is  only  able to  load
 *                 simple, 'primitive' types such  as String, Array, Hash, etc.
 *                 Never  allow  user  input  to  specify  arbitrary  types  to
 *                 deserialise into.
 */
VALUE rb_marshal_load(VALUE port);

/**
 * Marshal  format compatibility  layer.  Over  time, classes  evolve, so  that
 * their internal data structure change  drastically.  For instance an instance
 * of ::rb_cRange  was made  of ::RUBY_T_OBJECT  in 1.x.,  but in  3.x it  is a
 * ::RUBY_T_STRUCT now.  In  order to keep binary compatibility,  we "fake" the
 * marshalled representation to stick to old  types.  This is the API to enable
 * that manoeuvre.  Here is how:
 *
 * First, because  you are going to  keep backwards compatibility, you  need to
 * retain the old implementation of your  class.  Rename it, and keep the class
 * somewhere  (for  instance  rb_register_global_address() could  help).   Next
 * create your new class.  Do whatever you want.
 *
 * Then, this is the key point.  Create two new "bridge" functions that convert
 * the structs back and forth:
 *
 *   - the  "dumper" function  that takes  an instance  of the  new class,  and
 *     returns   an  instance   of  the   old   one.   This   is  called   from
 *     rb_marshal_dump(), to keep it possible for old programs to read your new
 *     data.
 *
 *   - the "loader" function that takes two  arguments, new one and old one, in
 *     that  order.  rb_marshal_load()  calls  this function  when  it finds  a
 *     representation of  the retained old class.   The old one passed  to this
 *     function   is   the   reconstructed   instance   of   the   old   class.
 *     Reverse-engineer  that to  modify the  new  one, to  have the  identical
 *     contents.
 *
 * Finally, connect all of them using this function.
 *
 * @param[in]  newclass       The class that needs conversion.
 * @param[in]  oldclass       Old implementation of `newclass`.
 * @param[in]  dumper         Function that converts `newclass` to `oldclass`.
 * @param[in]  loader         Function that converts `oldclass` to `newclass`.
 * @exception  rb_eTypeError  `newclass` has no allocator.
 */
void rb_marshal_define_compat(VALUE newclass, VALUE oldclass, VALUE (*dumper)(VALUE), VALUE (*loader)(VALUE, VALUE));

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_MARSHAL_H */
