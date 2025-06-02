#ifndef  RBIMPL_INTERN_LOAD_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define  RBIMPL_INTERN_LOAD_H
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
 * @brief      Public APIs related to ::rb_f_require().
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* load.c */

/**
 * Loads and executes the Ruby program in the given file.
 *
 * If the path is  an absolute path (e.g. starts with `'/'`),  the file will be
 * loaded  directly using  the  absolute  path.  If  the  path  is an  explicit
 * relative path (e.g. starts with `'./'`  or `'../'`), the file will be loaded
 * using the  relative path  from the current  directory.  Otherwise,  the file
 * will be searched for in the  library directories listed in the `$LOAD_PATH`.
 * If the file is found in a  directory, this function will attempt to load the
 * file relative  to that directory.  If  the file is  not found in any  of the
 * directories in the `$LOAD_PATH`, the file  will be loaded using the relative
 * path from the current directory.
 *
 * If the file doesn't  exist when there is an attempt to  load it, a LoadError
 * will be raised.
 *
 * If the `wrap` parameter is true, the loaded script will be executed under an
 * anonymous module, protecting the calling  program's global namespace.  In no
 * circumstance will  any local variables in  the loaded file be  propagated to
 * the loading environment.
 *
 * @param[in]  path                Pathname of a file to load.
 * @param[in]  wrap                Either to load under an anonymous module.
 * @exception  rb_eTypeError       `path` is not a string.
 * @exception  rb_eArgError        `path` is broken as a pathname.
 * @exception  rb_eEncCompatError  `path` is incompatible with pathnames.
 * @exception  rb_eLoadError       `path` not found.
 * @exception  rb_eException       Any exceptions while loading the contents.
 *
 * @internal
 *
 * It seems this function is under the rule of bootsnap's regime?
 */
void rb_load(VALUE path, int wrap);

/**
 * Identical to  rb_load(), except  it avoids  potential global  escapes.  Such
 * global escapes include exceptions, `throw`, `break`, for example.
 *
 * It first  evaluates the given file  as rb_load() does.  If  no global escape
 * occurred  during the  evaluation,  it `*state`  is set  to  zero on  return.
 * Otherwise, it sets `*state`  to nonzero.  If state is `NULL`,  it is not set
 * in both cases.
 *
 * @param[in]   path   Pathname of a file to load.
 * @param[in]   wrap   Either to load under an anonymous module.
 * @param[out]  state  State of execution.
 * @post        `*state` is set to zero if succeeded.  Nonzero otherwise.
 * @warning     You have to clear the error info with `rb_set_errinfo(Qnil)` if
 *              you decide to ignore the caught exception.
 * @see         rb_load
 * @see         rb_protect
 *
 * @internal
 *
 * Though   not  a   part  of   our  public   API,  `state`   is  in   fact  an
 * enum ruby_tag_type.  You can  see the potential "nonzero"  values by looking
 * at vm_core.h.
 */
void rb_load_protect(VALUE path, int wrap, int *state);

RBIMPL_ATTR_NONNULL(())
/**
 * Queries if  the given  feature has  already been  loaded into  the execution
 * context.  The "feature" head are things like `"json"` or `"socket"`.
 *
 * @param[in]  feature  Name of a library you want to know about.
 * @retval     1        Yes there is.
 * @retval     0        Not yet.
 */
int rb_provided(const char *feature);

RBIMPL_ATTR_NONNULL((1))
/**
 * Identical to  rb_provided(), except it additionally  returns the "canonical"
 * name of the loaded feature.  This can be handy when for instance you want to
 * know the actually loaded library is either `foo.rb` or `foo.so`.
 *
 * @param[in]   feature  Name of a library you want to know about.
 * @param[out]  loading  Return buffer.
 * @retval      1        Yes there is.
 * @retval      0        Not yet.
 */
int rb_feature_provided(const char *feature, const char **loading);

RBIMPL_ATTR_NONNULL(())
/**
 * Declares that the  given feature is already provided by  someone else.  This
 * API can  be handy  when you  have an extension  called `foo.so`  which, when
 * required, also provides functionality of `bar.so`.
 *
 * @param[in]  feature  Name of a library which had already been provided.
 * @post       No further `require` would search `feature`.
 */
void rb_provide(const char *feature);

/**
 * Identical to rb_require_string(),  except it ignores the  first argument for
 * no reason.  There seems to be no reason for 3rd party extension libraries to
 * use it.
 *
 * @param[in]  self              Ignored.  Can be anything.
 * @param[in]  feature           Name of a feature, e.g. `"json"`.
 * @exception  rb_eLoadError     No such feature.
 * @exception  rb_eRuntimeError  `$"` is frozen; unable to push.
 * @retval     RUBY_Qtrue        The feature is loaded for the first time.
 * @retval     RUBY_Qfalse       The feature has already been loaded.
 * @post       `$"` is updated.
 */
VALUE rb_f_require(VALUE self, VALUE feature);

/**
 * Finds and loads the given feature, if absent.
 *
 * If the  feature is an  absolute path (e.g.  starts with `'/'`),  the feature
 * will  be loaded  directly using  the absolute  path.  If  the feature  is an
 * explicit relative  path (e.g.  starts with `'./'`  or `'../'`),  the feature
 * will  be  loaded  using  the  relative  path  from  the  current  directory.
 * Otherwise,  the feature  will be  searched  for in  the library  directories
 * listed in the `$LOAD_PATH`.
 *
 * If the feature has the extension `".rb"`,  it is loaded as a source file; if
 * the extension is `".so"`, `".o"`, or `".dll"`, or the default shared library
 * extension on the  current platform, Ruby loads the shared  library as a Ruby
 * extension.  Otherwise, Ruby tries adding `".rb"`,  `".so"`, and so on to the
 * name until found.   If the file named  cannot be found, a  LoadError will be
 * raised.
 *
 * For  extension  libraries the  given  feature  may  use any  shared  library
 * extension.  For example, on Linux you can require `"socket.dll"` to actually
 * load `socket.so`.
 *
 * The absolute path of the loaded file is added to `$LOADED_FEATURES`.  A file
 * will not be loaded again if its path already appears in there.
 *
 * Any constants or globals within the  loaded source file will be available in
 * the calling program's  global namespace.  However, local  variables will not
 * be propagated to the loading environment.
 *
 * @param[in]  feature           Name of a feature, e.g. `"json"`.
 * @exception  rb_eLoadError     No such feature.
 * @exception  rb_eRuntimeError  `$"` is frozen; unable to push.
 * @retval     RUBY_Qtrue        The feature is loaded for the first time.
 * @retval     RUBY_Qfalse       The feature has already been loaded.
 * @post       `$"` is updated.
 */
VALUE rb_require_string(VALUE feature);

/**
 * @name extension configuration
 * @{
 */

/**
 * Asserts that  the extension  library that  calls this  function is  aware of
 * Ractor.  Multiple Ractors  run without protecting each  other.  This doesn't
 * interface  well   with  C  programs,   unless  designed  with   an  in-depth
 * understanding of  how Ractors work.   Extension libraries are shut  out from
 * Ractors by default.  This API is  to bypass that restriction.  Once after it
 * was called,  successive calls to rb_define_method()  etc. become definitions
 * of methods  that are  aware of  Ractors.  The amendment  would be  in effect
 * until the end of rb_require_string() etc.
 *
 * @param[in]  flag  Either the library is aware of Ractors or not.
 * @post       Methods would be callable form Ractors, if `flag` is true.
 */
void rb_ext_ractor_safe(bool flag);

/** @alias{rb_ext_ractor_safe} */
#define RB_EXT_RACTOR_SAFE(f) rb_ext_ractor_safe(f)

/**
 * This macro  is to provide  backwards compatibility.  It  must be safe  to do
 * something like:
 *
 * ```CXX
 * #ifdef HAVE_RB_EXT_RACTOR_SAFE
 * rb_ext_ractor_safe(true);
 * #endif
 * ```
 */
#define HAVE_RB_EXT_RACTOR_SAFE 1

/** @} */

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_LOAD_H */
