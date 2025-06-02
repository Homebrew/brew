#ifndef RBIMPL_INTERN_PARSE_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_PARSE_H
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
 * @brief      Public APIs related to ::rb_cSymbol.
 */
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* symbol.c */

/**
 * Calculates an ID of attribute writer.   For instance it returns `:foo=` when
 * passed `:foo`.
 *
 * @param[in]  id             An id.
 * @exception  rb_eNameError  `id` is not for attributes (e.g. operator).
 * @return     Calculated name of attribute writer.
 */
ID rb_id_attrset(ID id);

RBIMPL_ATTR_CONST()
/**
 * Classifies the given ID, then sees if it is a constant.  In case an ID is in
 * Unicode (likely), its  "constant"-ness is determined if  its first character
 * is  either upper  case or  title case.   Otherwise it  is detected  if case-
 * folding the first character changes its case or not.
 *
 * @param[in]  id  An id to classify.
 * @retval     1   It is a constant.
 * @retval     0   It isn't.
 */
int rb_is_const_id(ID id);

RBIMPL_ATTR_CONST()
/**
 * Classifies the  given ID, then  sees if it is  a global variable.   A global
 * variable must start with `$`.
 *
 * @param[in]  id  An id to classify.
 * @retval     1   It is a global variable.
 * @retval     0   It isn't.
 */
int rb_is_global_id(ID id);

RBIMPL_ATTR_CONST()
/**
 * Classifies  the given  ID, then  sees  if it  is an  instance variable.   An
 * instance variable must start with `@`, but not `@@`.
 *
 * @param[in]  id  An id to classify.
 * @retval     1   It is an instance variable.
 * @retval     0   It isn't.
 */
int rb_is_instance_id(ID id);

RBIMPL_ATTR_CONST()
/**
 * Classifies  the given  ID,  then sees  if  it is  an  attribute writer.   An
 * attribute writer is otherwise a local variable, except it ends with `=`.
 *
 * @param[in]  id  An id to classify.
 * @retval     1   It is an attribute writer.
 * @retval     0   It isn't.
 */
int rb_is_attrset_id(ID id);

RBIMPL_ATTR_CONST()
/**
 * Classifies the  given ID,  then sees  if it  is a  class variable.   A class
 * variable is must start with `@@`.
 *
 * @param[in]  id  An id to classify.
 * @retval     1   It is a class variable.
 * @retval     0   It isn't.
 */
int rb_is_class_id(ID id);

RBIMPL_ATTR_CONST()
/**
 * Classifies the  given ID,  then sees  if it  is a  local variable.   A local
 * variable starts  with a lowercase  character, followed by  some alphanumeric
 * characters or `_`, then ends with anything other than `!`, `?`, or `=`.
 *
 * @param[in]  id  An id to classify.
 * @retval     1   It is a local variable.
 * @retval     0   It isn't.
 */
int rb_is_local_id(ID id);

RBIMPL_ATTR_CONST()
/**
 * Classifies the  given ID,  then sees  if it  is a  junk ID.   An ID  with no
 * special syntactic structure is considered  junk.  This category includes for
 * instance punctuation.
 *
 * @param[in]  id  An id to classify.
 * @retval     1   It is a junk.
 * @retval     0   It isn't.
 */
int rb_is_junk_id(ID);

RBIMPL_ATTR_NONNULL(())
/**
 * Sees if  the passed C string  constructs a valid syntactic  symbol.  Invalid
 * ones for instance includes whitespaces.
 *
 * @param[in]  str  A C string to check.
 * @retval     1    It is a valid symbol name.
 * @retval     0    It is invalid as a symbol name.
 */
int rb_symname_p(const char *str);

/* vm.c */

/**
 * Queries the last match, or `Regexp.last_match`, or the `$~`.  You don't have
 * to use it, because in reality you can get `$~` using rb_gv_get() as usual.
 *
 * @retval  RUBY_Qnil  The method has not ran a regular expression.
 * @retval  otherwise  An instance of ::rb_cMatch.
 */
VALUE rb_backref_get(void);

/**
 * Updates `$~`.  You don't have to use it, because in reality you can set `$~`
 * using rb_gv_set() as usual.
 *
 * @param[in]  md  Arbitrary Ruby object.
 * @post       The passed object is assigned to `$~`.
 *
 * @internal
 *
 * Yes, this  function bypasses  the Check_Type()  that would  normally prevent
 * evil souls from assigning  evil objects to `$~`.  Use of  this function is a
 * really bad smell.
 */
void rb_backref_set(VALUE md);

/**
 * Queries the last  line, or the `$_`.   You don't have to use  it, because in
 * reality you can get `$_` using rb_gv_get() as usual.
 *
 * @retval  RUBY_Qnil  There has never been a "line" yet.
 * @retval  otherwise  The last set `$_` value.
 */
VALUE rb_lastline_get(void);

/**
 * Updates `$_`.  You don't have to use it, because in reality you can set `$_`
 * using rb_gv_set() as usual.
 *
 * @param[in]  str  Arbitrary Ruby object.
 * @post       The passed object is assigned to `$_`.
 *
 * @internal
 *
 * Unlike `$~`, you can assign non-strings to `$_`, even from ruby scripts.
 */
void rb_lastline_set(VALUE str);

/* symbol.c */

/**
 * Collects every single bits of symbols  that have ever interned in the entire
 * history of the current process.
 *
 * @return  An array that contains all symbols that have ever existed.
 */
VALUE rb_sym_all_symbols(void);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_PARSE_H */
