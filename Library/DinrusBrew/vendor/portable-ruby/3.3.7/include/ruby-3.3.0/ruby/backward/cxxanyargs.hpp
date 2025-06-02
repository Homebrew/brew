#ifndef RUBY_BACKWARD_CXXANYARGS_HPP                       //-*-C++-*-vi:ft=cpp
#define RUBY_BACKWARD_CXXANYARGS_HPP
/// @file
/// @author     @shyouhei
/// @copyright  This  file  is  a  part   of  the  programming  language  Ruby.
///             Permission  is hereby  granted, to  either redistribute  and/or
///             modify this file, provided that the conditions mentioned in the
///             file COPYING are met.  Consult the file for details.
/// @note       DO NOT  MODERNISE THIS FILE!   As the  file name implies  it is
///             meant to  be a backwards  compatibility shim.  Please  stick to
///             C++ 98 and never use newer features, like `constexpr`.
/// @brief      Provides old prototypes for C++ programs.
#include "ruby/internal/config.h"
#include "ruby/internal/intern/class.h"
#include "ruby/internal/intern/cont.h"
#include "ruby/internal/intern/hash.h"
#include "ruby/internal/intern/proc.h"
#include "ruby/internal/intern/thread.h"
#include "ruby/internal/intern/variable.h"
#include "ruby/internal/intern/vm.h"
#include "ruby/internal/iterator.h"
#include "ruby/internal/method.h"
#include "ruby/internal/value.h"
#include "ruby/internal/variable.h"
#include "ruby/backward/2/stdarg.h"
#include "ruby/st.h"

extern "C++" {

#ifdef HAVE_NULLPTR
#include <cstddef>
#endif

/// @brief  The main namespace.
/// @note   The name  "ruby" might  already be  taken, but that  must not  be a
///         problem because namespaces are allowed to reopen.
namespace ruby {

/// Backwards compatibility layer.
namespace backward {

/// Provides ANYARGS  deprecation warnings.   In C, ANYARGS  means there  is no
/// function prototype.  Literally  anything, even including nothing,  can be a
/// valid ANYARGS.   So passing a  correctly prototyped function pointer  to an
/// ANYARGS-ed  function  parameter is  valid,  at  the  same time  passing  an
/// ANYARGS-ed function pointer to a  granular typed function parameter is also
/// valid.  However on the other hand in C++, ANYARGS doesn't actually mean any
/// number of arguments.   C++'s ANYARGS means _variadic_  number of arguments.
/// This is incompatible with ordinal, correct function prototypes.
///
/// Luckily, function  prototypes being distinct  each other means they  can be
/// overloaded.  We can provide a compatibility layer for older Ruby APIs which
/// used to have ANYARGS.  This namespace includes such attempts.
namespace cxxanyargs {

typedef VALUE type(ANYARGS);      ///< ANYARGS-ed function type.
typedef void void_type(ANYARGS);  ///< ANYARGS-ed function type, void variant.
typedef int int_type(ANYARGS);    ///< ANYARGS-ed function type, int variant.
typedef VALUE onearg_type(VALUE); ///< Single-argumented function type.

/// @name Hooking global variables
/// @{

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Define a function-backended global variable.
/// @param[in]   q  Name of the variable.
/// @param[in]   w  Getter function.
/// @param[in]   e  Setter function.
/// @note        Both functions can be nullptr.
/// @see         rb_define_hooked_variable()
/// @deprecated  Use granular typed overload instead.
inline void
rb_define_virtual_variable(const char *q, type *w, void_type *e)
{
    rb_gvar_getter_t *r = reinterpret_cast<rb_gvar_getter_t*>(w);
    rb_gvar_setter_t *t = reinterpret_cast<rb_gvar_setter_t*>(e);
    ::rb_define_virtual_variable(q, r, t);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
inline void
rb_define_virtual_variable(const char *q, rb_gvar_getter_t *w, void_type *e)
{
    rb_gvar_setter_t *t = reinterpret_cast<rb_gvar_setter_t*>(e);
    ::rb_define_virtual_variable(q, w, t);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
inline void
rb_define_virtual_variable(const char *q, type *w, rb_gvar_setter_t *e)
{
    rb_gvar_getter_t *r = reinterpret_cast<rb_gvar_getter_t*>(w);
    ::rb_define_virtual_variable(q, r, e);
}

#ifdef HAVE_NULLPTR
inline void
rb_define_virtual_variable(const char *q, rb_gvar_getter_t *w, std::nullptr_t e)
{
    ::rb_define_virtual_variable(q, w, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
inline void
rb_define_virtual_variable(const char *q, type *w, std::nullptr_t e)
{
    rb_gvar_getter_t *r = reinterpret_cast<rb_gvar_getter_t *>(w);
    ::rb_define_virtual_variable(q, r, e);
}

inline void
rb_define_virtual_variable(const char *q, std::nullptr_t w, rb_gvar_setter_t *e)
{
    ::rb_define_virtual_variable(q, w, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
inline void
rb_define_virtual_variable(const char *q, std::nullptr_t w, void_type *e)
{
    rb_gvar_setter_t *r = reinterpret_cast<rb_gvar_setter_t *>(e);
    ::rb_define_virtual_variable(q, w, r);
}
#endif

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Define a function-backended global variable.
/// @param[in]   q  Name of the variable.
/// @param[in]   w  Variable storage.
/// @param[in]   e  Getter function.
/// @param[in]   r  Setter function.
/// @note        Both functions can be nullptr.
/// @see         rb_define_virtual_variable()
/// @deprecated  Use granular typed overload instead.
inline void
rb_define_hooked_variable(const char *q, VALUE *w, type *e, void_type *r)
{
    rb_gvar_getter_t *t = reinterpret_cast<rb_gvar_getter_t*>(e);
    rb_gvar_setter_t *y = reinterpret_cast<rb_gvar_setter_t*>(r);
    ::rb_define_hooked_variable(q, w, t, y);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
inline void
rb_define_hooked_variable(const char *q, VALUE *w, rb_gvar_getter_t *e, void_type *r)
{
    rb_gvar_setter_t *y = reinterpret_cast<rb_gvar_setter_t*>(r);
    ::rb_define_hooked_variable(q, w, e, y);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
inline void
rb_define_hooked_variable(const char *q, VALUE *w, type *e, rb_gvar_setter_t *r)
{
    rb_gvar_getter_t *t = reinterpret_cast<rb_gvar_getter_t*>(e);
    ::rb_define_hooked_variable(q, w, t, r);
}

#ifdef HAVE_NULLPTR
inline void
rb_define_hooked_variable(const char *q, VALUE *w, rb_gvar_getter_t *e, std::nullptr_t r)
{
    ::rb_define_hooked_variable(q, w, e, r);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
inline void
rb_define_hooked_variable(const char *q, VALUE *w, type *e, std::nullptr_t r)
{
    rb_gvar_getter_t *y = reinterpret_cast<rb_gvar_getter_t *>(e);
    ::rb_define_hooked_variable(q, w, y, r);
}

inline void
rb_define_hooked_variable(const char *q, VALUE *w, std::nullptr_t e, rb_gvar_setter_t *r)
{
    ::rb_define_hooked_variable(q, w, e, r);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
inline void
rb_define_hooked_variable(const char *q, VALUE *w, std::nullptr_t e, void_type *r)
{
    rb_gvar_setter_t *y = reinterpret_cast<rb_gvar_setter_t *>(r);
    ::rb_define_hooked_variable(q, w, e, y);
}
#endif

/// @}
/// @name Exceptions and tag jumps
/// @{

// RUBY_CXX_DEPRECATED("by rb_block_call since 1.9")
RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Old way to implement iterators.
/// @param[in]   q  A function that can yield.
/// @param[in]   w  Passed to `q`.
/// @param[in]   e  What is to be yielded.
/// @param[in]   r  Passed to `e`.
/// @return      The return value of `q`.
/// @note        `e` can be nullptr.
/// @deprecated  This function is obsoleted since  long before 2.x era.  Do not
///              use it any longer.  rb_block_call() is provided instead.
inline VALUE
rb_iterate(onearg_type *q, VALUE w, type *e, VALUE r)
{
    rb_block_call_func_t t = reinterpret_cast<rb_block_call_func_t>(e);
    return backward::rb_iterate_deprecated(q, w, t, r);
}

#ifdef HAVE_NULLPTR
RUBY_CXX_DEPRECATED("by rb_block_call since 1.9")
inline VALUE
rb_iterate(onearg_type *q, VALUE w, std::nullptr_t e, VALUE r)
{
    return backward::rb_iterate_deprecated(q, w, e, r);
}
#endif

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Call a method with a block.
/// @param[in]   q  The self.
/// @param[in]   w  The method.
/// @param[in]   e  The # of elems of `r`
/// @param[in]   r  The arguments.
/// @param[in]   t  What is to be yielded.
/// @param[in]   y  Passed to `t`
/// @return      Return value of `q#w(*r,&t)`
/// @note        't' can be nullptr.
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_block_call(VALUE q, ID w, int e, const VALUE *r, type *t, VALUE y)
{
    rb_block_call_func_t u = reinterpret_cast<rb_block_call_func_t>(t);
    return ::rb_block_call(q, w, e, r, u, y);
}

#ifdef HAVE_NULLPTR
inline VALUE
rb_block_call(VALUE q, ID w, int e, const VALUE *r, std::nullptr_t t, VALUE y)
{
    return ::rb_block_call(q, w, e, r, t, y);
}
#endif

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       An equivalent of `rescue` clause.
/// @param[in]   q  A function that can raise.
/// @param[in]   w  Passed to `q`.
/// @param[in]   e  A function that cleans-up.
/// @param[in]   r  Passed to `e`.
/// @return      The return value of `q` if  no exception occurs, or the return
///              value of `e` if otherwise.
/// @note        `e` can be nullptr.
/// @see         rb_ensure()
/// @see         rb_rescue2()
/// @see         rb_protect()
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_rescue(type *q, VALUE w, type *e, VALUE r)
{
    typedef VALUE func1_t(VALUE);
    typedef VALUE func2_t(VALUE, VALUE);
    func1_t *t = reinterpret_cast<func1_t*>(q);
    func2_t *y = reinterpret_cast<func2_t*>(e);
    return ::rb_rescue(t, w, y, r);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       An equivalent of `rescue` clause.
/// @param[in]   q    A function that can raise.
/// @param[in]   w    Passed to `q`.
/// @param[in]   e    A function that cleans-up.
/// @param[in]   r    Passed to `e`.
/// @param[in]   ...  0-terminated list of subclass of @ref rb_eException.
/// @return      The return value of `q` if  no exception occurs, or the return
///              value of `e` if otherwise.
/// @note        `e` can be nullptr.
/// @see         rb_ensure()
/// @see         rb_rescue()
/// @see         rb_protect()
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_rescue2(type *q, VALUE w, type *e, VALUE r, ...)
{
    typedef VALUE func1_t(VALUE);
    typedef VALUE func2_t(VALUE, VALUE);
    func1_t *t = reinterpret_cast<func1_t*>(q);
    func2_t *y = reinterpret_cast<func2_t*>(e);
    va_list ap;
    va_start(ap, r);
    VALUE ret = ::rb_vrescue2(t, w, y, r, ap);
    va_end(ap);
    return ret;
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       An equivalent of `ensure` clause.
/// @param[in]   q  A function that can raise.
/// @param[in]   w  Passed to `q`.
/// @param[in]   e  A function that ensures.
/// @param[in]   r  Passed to `e`.
/// @return      The return value of `q`.
/// @note        It makes no sense to pass nullptr to `e`.
/// @see         rb_rescue()
/// @see         rb_rescue2()
/// @see         rb_protect()
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_ensure(type *q, VALUE w, type *e, VALUE r)
{
    typedef VALUE func1_t(VALUE);
    func1_t *t = reinterpret_cast<func1_t*>(q);
    func1_t *y = reinterpret_cast<func1_t*>(e);
    return ::rb_ensure(t, w, y, r);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       An equivalent of `Kernel#catch`.
/// @param[in]   q  The "tag" string.
/// @param[in]   w  A function that can throw.
/// @param[in]   e  Passed to `w`.
/// @return      What was thrown.
/// @note        `q` can be a nullptr but makes no sense to pass nullptr to`w`.
/// @see         rb_block_call()
/// @see         rb_protect()
/// @see         rb_rb_catch_obj()
/// @see         rb_rescue()
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_catch(const char *q, type *w, VALUE e)
{
    rb_block_call_func_t r = reinterpret_cast<rb_block_call_func_t>(w);
    return ::rb_catch(q, r, e);
}

#ifdef HAVE_NULLPTR
inline VALUE
rb_catch(const char *q, std::nullptr_t w, VALUE e)
{
    return ::rb_catch(q, w, e);
}
#endif

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       An equivalent of `Kernel#catch`.
/// @param[in]   q  The "tag" object.
/// @param[in]   w  A function that can throw.
/// @param[in]   e  Passed to `w`.
/// @return      What was thrown.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         rb_block_call()
/// @see         rb_protect()
/// @see         rb_rb_catch_obj()
/// @see         rb_rescue()
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_catch_obj(VALUE q, type *w, VALUE e)
{
    rb_block_call_func_t r = reinterpret_cast<rb_block_call_func_t>(w);
    return ::rb_catch_obj(q, r, e);
}

/// @}
/// @name Procs, Fibers and Threads
/// @{

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Creates a rb_cFiber instance.
/// @param[in]   q  The fiber body.
/// @param[in]   w  Passed to `q`.
/// @return      What was allocated.
/// @note        It makes no sense to pass nullptr to`q`.
/// @see         rb_proc_new()
/// @see         rb_thread_create()
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_fiber_new(type *q, VALUE w)
{
    rb_block_call_func_t e = reinterpret_cast<rb_block_call_func_t>(q);
    return ::rb_fiber_new(e, w);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Creates a @ref rb_cProc instance.
/// @param[in]   q  The proc body.
/// @param[in]   w  Passed to `q`.
/// @return      What was allocated.
/// @note        It makes no sense to pass nullptr to`q`.
/// @see         rb_fiber_new()
/// @see         rb_thread_create()
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_proc_new(type *q, VALUE w)
{
    rb_block_call_func_t e = reinterpret_cast<rb_block_call_func_t>(q);
    return ::rb_proc_new(e, w);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Creates a @ref rb_cThread instance.
/// @param[in]   q  The thread body.
/// @param[in]   w  Passed to `q`.
/// @return      What was allocated.
/// @note        It makes no sense to pass nullptr to`q`.
/// @see         rb_proc_new()
/// @see         rb_fiber_new()
/// @deprecated  Use granular typed overload instead.
inline VALUE
rb_thread_create(type *q, void *w)
{
    typedef VALUE ptr_t(void*);
    ptr_t *e = reinterpret_cast<ptr_t*>(q);
    return ::rb_thread_create(e, w);
}

/// @}
/// @name Hash and st_table
/// @{

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Iteration over the given table.
/// @param[in]   q  A table to scan.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @retval      0  Always returns 0.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach_check()
/// @see         rb_hash_foreach()
/// @deprecated  Use granular typed overload instead.
inline int
st_foreach(st_table *q, int_type *w, st_data_t e)
{
    st_foreach_callback_func *r =
        reinterpret_cast<st_foreach_callback_func*>(w);
    return ::st_foreach(q, r, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Iteration over the given table.
/// @param[in]   q  A table to scan.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @retval      0  Successful end of iteration.
/// @retval      1  Element removed during traversing.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach()
/// @deprecated  Use granular typed overload instead.
inline int
st_foreach_check(st_table *q, int_type *w, st_data_t e, st_data_t)
{
    st_foreach_check_callback_func *t =
        reinterpret_cast<st_foreach_check_callback_func*>(w);
    return ::st_foreach_check(q, t, e, 0);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Iteration over the given table.
/// @param[in]   q  A table to scan.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach_check()
/// @deprecated  Use granular typed overload instead.
inline void
st_foreach_safe(st_table *q, int_type *w, st_data_t e)
{
    st_foreach_callback_func *r =
        reinterpret_cast<st_foreach_callback_func*>(w);
    ::st_foreach_safe(q, r, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Iteration over the given hash.
/// @param[in]   q  A hash to scan.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach()
/// @deprecated  Use granular typed overload instead.
inline void
rb_hash_foreach(VALUE q, int_type *w, VALUE e)
{
    st_foreach_callback_func *r =
        reinterpret_cast<st_foreach_callback_func*>(w);
    ::rb_hash_foreach(q, r, e);
}

RUBY_CXX_DEPRECATED("Use of ANYARGS in this function is deprecated")
/// @brief       Iteration over each instance variable of the object.
/// @param[in]   q  An object.
/// @param[in]   w  A function to iterate.
/// @param[in]   e  Passed to `w`.
/// @note        It makes no sense to pass nullptr to`w`.
/// @see         st_foreach()
/// @deprecated  Use granular typed overload instead.
inline void
rb_ivar_foreach(VALUE q, int_type *w, VALUE e)
{
    st_foreach_callback_func *r =
        reinterpret_cast<st_foreach_callback_func*>(w);
    ::rb_ivar_foreach(q, r, e);
}

/// @}

/// Driver for *_define_method.  ::rb_define_method function for instance takes
/// a  pointer to  ANYARGS-ed  functions,  which in  fact  varies 18  different
/// prototypes.  We  still need to  preserve ANYARGS  for storages but  why not
/// check  the consistencies  if  possible.   In C++  a  function  has its  own
/// prototype, which  is a compile-time  constant (static type) by  nature.  We
/// can list  up all the  possible input types  and provide warnings  for other
/// cases.  This is such attempt.
namespace define_method {

/// Type of ::rb_f_notimplement().
typedef VALUE notimpl_type(int, const VALUE *, VALUE, VALUE);

/// @brief   Template metaprogramming to generate function prototypes.
/// @tparam  T  Type of method id (`ID` or `const char*` in practice).
/// @tparam  F  Definition driver e.g. ::rb_define_method.
template<typename T, void (*F)(VALUE klass, T mid, type *func, int arity)>
struct driver {

    /// @brief      Defines a method
    /// @tparam     N  Arity of the function.
    /// @tparam     U  The function in question
    template<int N, typename U>
    struct engine {

        /* :TODO: Following deprecation attribute renders tons of warnings (one
         * per  every  method  definitions),  which  is  annoying.   Of  course
         * annoyance is the  core feature of deprecation  warnings...  But that
         * could be  too much,  especially when the  warnings happen  inside of
         * machine-generated programs.   And SWIG  is known  to do  such thing.
         * The new  (granular) API was  introduced in  API version 2.7.   As of
         * this writing the  version is 2.8.  Let's warn this  later, some time
         * during 3.x.   Hopefully codes in  old (ANYARGS-ed) format  should be
         * less than now. */
#if (RUBY_API_VERSION_MAJOR * 100 + RUBY_API_VERSION_MINOR) >= 301
        RUBY_CXX_DEPRECATED("use of ANYARGS is deprecated")
#endif
        /// @copydoc define(VALUE klass, T mid, U func)
        /// @deprecated  Pass correctly typed function instead.
        static inline void
        define(VALUE klass, T mid, type func)
        {
            F(klass, mid, func, N);
        }

        /// @brief      Defines klass#mid as func, whose arity is N.
        /// @param[in]  klass  Where the method lives.
        /// @param[in]  mid    Name of the method to define.
        /// @param[in]  func   Function that implements klass#mid.
        static inline void
        define(VALUE klass, T mid, U func)
        {
            F(klass, mid, reinterpret_cast<type *>(func), N);
        }

        /// @copydoc define(VALUE klass, T mid, U func)
        static inline void
        define(VALUE klass, T mid, notimpl_type func)
        {
            F(klass, mid, reinterpret_cast<type *>(func), N);
        }
    };

    /// @cond INTERNAL_MACRO
    template<int N, bool = false> struct specific : public engine<N, type *> {};
    template<bool b> struct specific<15, b> : public engine<15, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<14, b> : public engine<14, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<13, b> : public engine<13, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<12, b> : public engine<12, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<11, b> : public engine<11, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<10, b> : public engine<10, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 9, b> : public engine< 9, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 8, b> : public engine< 8, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 7, b> : public engine< 7, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 6, b> : public engine< 6, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 5, b> : public engine< 5, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 4, b> : public engine< 4, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 3, b> : public engine< 3, VALUE(*)(VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 2, b> : public engine< 2, VALUE(*)(VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 1, b> : public engine< 1, VALUE(*)(VALUE, VALUE)> {};
    template<bool b> struct specific< 0, b> : public engine< 0, VALUE(*)(VALUE)> {};
    template<bool b> struct specific<-1, b> : public engine<-1, VALUE(*)(int argc, VALUE *argv, VALUE self)> {
        using engine<-1, VALUE(*)(int argc, VALUE *argv, VALUE self)>::define;
        static inline void define(VALUE c, T m, VALUE(*f)(int argc, const VALUE *argv, VALUE self)) { F(c, m, reinterpret_cast<type *>(f), -1); }
    };
    template<bool b> struct specific<-2, b> : public engine<-2, VALUE(*)(VALUE, VALUE)> {};
    /// @endcond
};

/* We could perhaps merge this struct into the one above using variadic
 * template parameters if we could assume C++11, but sadly we cannot. */
/// @copydoc ruby::backward::cxxanyargs::define_method::driver
template<typename T, void (*F)(T mid, type func, int arity)>
struct driver0 {

    /// @brief      Defines a method
    /// @tparam     N  Arity of the function.
    /// @tparam     U  The function in question
    template<int N, typename U>
    struct engine {
        RUBY_CXX_DEPRECATED("use of ANYARGS is deprecated")
        /// @copydoc define(T mid, U func)
        /// @deprecated  Pass correctly typed function instead.
        static inline void
        define(T mid, type func)
        {
            F(mid, func, N);
        }

        /// @brief      Defines Kernel#mid as func, whose arity is N.
        /// @param[in]  mid    Name of the method to define.
        /// @param[in]  func   Function that implements klass#mid.
        static inline void
        define(T mid, U func)
        {
            F(mid, reinterpret_cast<type *>(func), N);
        }

        /// @copydoc define(T mid, U func)
        /// @deprecated  Pass correctly typed function instead.
        static inline void
        define(T mid, notimpl_type func)
        {
            F(mid, reinterpret_cast<type *>(func), N);
        }
    };

    /// @cond INTERNAL_MACRO
    template<int N, bool = false> struct specific : public engine<N, type *> {};
    template<bool b> struct specific<15, b> : public engine<15, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<14, b> : public engine<14, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<13, b> : public engine<13, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<12, b> : public engine<12, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<11, b> : public engine<11, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific<10, b> : public engine<10, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 9, b> : public engine< 9, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 8, b> : public engine< 8, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 7, b> : public engine< 7, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 6, b> : public engine< 6, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 5, b> : public engine< 5, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 4, b> : public engine< 4, VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 3, b> : public engine< 3, VALUE(*)(VALUE, VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 2, b> : public engine< 2, VALUE(*)(VALUE, VALUE, VALUE)> {};
    template<bool b> struct specific< 1, b> : public engine< 1, VALUE(*)(VALUE, VALUE)> {};
    template<bool b> struct specific< 0, b> : public engine< 0, VALUE(*)(VALUE)> {};
    template<bool b> struct specific<-1, b> : public engine<-1, VALUE(*)(int argc, VALUE *argv, VALUE self)> {
        using engine<-1, VALUE(*)(int argc, VALUE *argv, VALUE self)>::define;
        static inline void define(T m, VALUE(*f)(int argc, const VALUE *argv, VALUE self)) { F(m, reinterpret_cast<type *>(f), -1); }
    };
    template<bool b> struct specific<-2, b> : public engine<-2, VALUE(*)(VALUE, VALUE)> {};
    /// @endcond
};

struct rb_define_method           : public driver <const char *, ::rb_define_method> {};           ///< Dispatches appropriate driver for ::rb_define_method.
struct rb_define_method_id        : public driver <ID,           ::rb_define_method_id> {};        ///< Dispatches appropriate driver for ::rb_define_method_id.
struct rb_define_private_method   : public driver <const char *, ::rb_define_private_method> {};   ///< Dispatches appropriate driver for ::rb_define_private_method.
struct rb_define_protected_method : public driver <const char *, ::rb_define_protected_method> {}; ///< Dispatches appropriate driver for ::rb_define_protected_method.
struct rb_define_singleton_method : public driver <const char *, ::rb_define_singleton_method> {}; ///< Dispatches appropriate driver for ::rb_define_singleton_method.
struct rb_define_module_function  : public driver <const char *, ::rb_define_module_function> {};  ///< Dispatches appropriate driver for ::rb_define_module_function.
struct rb_define_global_function  : public driver0<const char *, ::rb_define_global_function> {};  ///< Dispatches appropriate driver for ::rb_define_global_function.

/// @brief        Defines klass\#mid.
/// @param        klass  Where the method lives.
/// @copydetails  #rb_define_global_function(mid, func, arity)
#define rb_define_method(klass, mid, func, arity)           ::ruby::backward::cxxanyargs::define_method::rb_define_method::specific<arity>::define(klass, mid, func)

/// @copydoc #rb_define_method(klass, mid, func, arity)
#define rb_define_method_id(klass, mid, func, arity)        ::ruby::backward::cxxanyargs::define_method::rb_define_method_id::specific<arity>::define(klass, mid, func)

/// @brief        Defines klass\#mid and makes it private.
/// @copydetails  #rb_define_method(klass, mid, func, arity)
#define rb_define_private_method(klass, mid, func, arity)   ::ruby::backward::cxxanyargs::define_method::rb_define_private_method::specific<arity>::define(klass, mid, func)

/// @brief        Defines klass\#mid and makes it protected.
/// @copydetails  #rb_define_method
#define rb_define_protected_method(klass, mid, func, arity) ::ruby::backward::cxxanyargs::define_method::rb_define_protected_method::specific<arity>::define(klass, mid, func)

/// @brief        Defines klass.mid.(klass, mid, func, arity)
/// @copydetails  #rb_define_method
#define rb_define_singleton_method(klass, mid, func, arity) ::ruby::backward::cxxanyargs::define_method::rb_define_singleton_method::specific<arity>::define(klass, mid, func)

/// @brief        Defines klass\#mid and makes it a module function.
/// @copydetails  #rb_define_method(klass, mid, func, arity)
#define rb_define_module_function(klass, mid, func, arity)  ::ruby::backward::cxxanyargs::define_method::rb_define_module_function::specific<arity>::define(klass, mid, func)

/// @brief Defines ::rb_mKernel \#mid.
/// @param mid    Name of the defining method.
/// @param func   Implementation of \#mid.
/// @param arity  Arity of \#mid.
#define rb_define_global_function(mid, func, arity)         ::ruby::backward::cxxanyargs::define_method::rb_define_global_function::specific<arity>::define(mid, func)

}}}}}

using namespace ruby::backward::cxxanyargs;
#endif // RUBY_BACKWARD_CXXANYARGS_HPP
