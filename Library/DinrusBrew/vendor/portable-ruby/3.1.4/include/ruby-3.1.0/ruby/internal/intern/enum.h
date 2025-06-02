#ifndef RBIMPL_INTERN_ENUM_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_ENUM_H
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
 * @brief      Public APIs related to ::rb_mEnumerable.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* enum.c */

/**
 * Basically identical to rb_ary_new_form_values(), except it returns something
 * different when `argc` < 2.
 *
 * @param[in]  argc       Number of objects of `argv`.
 * @param[in]  argv       Arbitrary objects.
 * @retval     RUBY_Qnil  `argc` is zero.
 * @retval     argv[0]    `argc` is one.
 * @retval     otherwise  Otherwise.
 *
 * @internal
 *
 * What  is this  business?   Well,  this function  is  about `yield`'s  taking
 * multiple values.  Consider following user-defined class:
 *
 * ```ruby
 * class Foo
 *   include Enumerable
 *
 *   def each
 *     yield :q, :w, :e, :r
 *   end
 * end
 *
 * Foo.new.each_with_object([]) do |i, j|
 *   j << i                      # ^^^ <- What to expect for `i`?
 * end
 * ```
 *
 * Here, `Foo#each_with_object` is in fact `Enumerable#each_with_object`, which
 * doesn't know what would be yielded.  Yet, it has to take a block of arity 2.
 * This function  is used here, to  "pack" arbitrary number of  yielded objects
 * into one.
 *
 * If people want to implement their own `Enumerable#each_with_object` this API
 * can be handy.  Though @shyouhei suspects it is relatively rare for 3rd party
 * extension libraries  to have  such things.  Also  `Enumerable#each_entry` is
 * basically this function exposed as a Ruby method.
 */
VALUE rb_enum_values_pack(int argc, const VALUE *argv);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_ENUM_H */
