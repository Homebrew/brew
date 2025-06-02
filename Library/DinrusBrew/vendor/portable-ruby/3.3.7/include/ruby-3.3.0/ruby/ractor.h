#ifndef RUBY_RACTOR_H                                /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_RACTOR_H 1

/**
 * @file
 * @author Koichi Sasada
 * @date Tue Nov 17 16:39:15 2020
 * @copyright Copyright (C) 2020 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "internal/dllexport.h"      /* RUBY_EXTERN is here */
#include "internal/fl_type.h"        /* FL_TEST_RAW is here */
#include "internal/special_consts.h" /* RB_SPECIAL_CONSTS_P is here */
#include "internal/stdbool.h"        /* bool is here */
#include "internal/value.h"          /* VALUE is here */

/** Type that defines a ractor-local storage. */
struct rb_ractor_local_storage_type {

    /**
     * A function to mark a ractor-local storage.
     *
     * @param[out]  ptr  A ractor-local storage.
     * @post        Ruby objects inside of `ptr` are marked.
     */
    void (*mark)(void *ptr);

    /**
     * A function to destruct a ractor-local storage.
     *
     * @param[out]  ptr  A ractor-local storage.
     * @post        `ptr` is not a valid pointer.
     */
    void (*free)(void *ptr);
    // TODO: update
};

/** (Opaque) struct that holds a ractor-local storage key. */
typedef struct rb_ractor_local_key_struct *rb_ractor_local_key_t;

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * `Ractor` class.
 *
 * @ingroup object
 */
RUBY_EXTERN VALUE rb_cRactor;

/**
 * Queries  the standard  input  of the  current Ractor  that  is calling  this
 * function.
 *
 * @return  An IO.
 * @note    This can be different from the process-global one.
 */
VALUE rb_ractor_stdin(void);

/**
 * Queries  the standard  output of  the current  Ractor that  is calling  this
 * function.
 *
 * @return  An IO.
 * @note    This can be different from the process-global one.
 */
VALUE rb_ractor_stdout(void);

/**
 * Queries  the standard  error  of the  current Ractor  that  is calling  this
 * function.
 *
 * @return  An IO.
 * @note    This can be different from the process-global one.
 */
VALUE rb_ractor_stderr(void);

/**
 * Assigns an  IO to  the standard  input of  the Ractor  that is  calling this
 * function.
 *
 * @param[in]  io  An IO.
 * @post       `io` is the standard input of the current ractor.
 * @post       In case the  calling Ractor is the main Ractor,  it also updates
 *             the process global ::rb_stdin.
 */
void rb_ractor_stdin_set(VALUE io);

/**
 * Assigns an  IO to  the standard output  of the Ractor  that is  calling this
 * function.
 *
 * @param[in]  io  An IO.
 * @post       `io` is the standard input of the current ractor.
 * @post       In case the  calling Ractor is the main Ractor,  it also updates
 *             the process global ::rb_stdout.
 */
void rb_ractor_stdout_set(VALUE io);

/**
 * Assigns an  IO to  the standard  error of  the Ractor  that is  calling this
 * function.
 *
 * @param[in]  io  An IO.
 * @post       `io` is the standard input of the current ractor.
 * @post       In case the  calling Ractor is the main Ractor,  it also updates
 *             the process global ::rb_stderr.
 */
void rb_ractor_stderr_set(VALUE io);

/**
 * Issues a new key.
 *
 * @return  A newly  issued ractor-local storage  key.  Keys issued  using this
 *          key can be associated to a Ruby object per Ractor.
 */
rb_ractor_local_key_t rb_ractor_local_storage_value_newkey(void);

/**
 * Queries the key.
 *
 * @param[in]  key        A ractor-local storage key to lookup.
 * @retval     RUBY_Qnil  No such key.
 * @retval     otherwise  A value corresponds to `key` in the current Ractor.
 * @note       This  cannot distinguish  between a  nonexistent key  and a  key
 *             exists and corresponds to ::RUBY_Qnil.
 */
VALUE rb_ractor_local_storage_value(rb_ractor_local_key_t key);

/**
 * Queries the key.
 *
 * @param[in]   key    A ractor-local storage key to lookup.
 * @param[out]  val    Return value buffer.
 * @retval      false  `key` not found.
 * @retval      true   `key` found.
 * @post        `val` is updated so that it  has the value corresponds to `key`
 *              in the current Ractor.
 */
bool rb_ractor_local_storage_value_lookup(rb_ractor_local_key_t key, VALUE *val);

/**
 * Associates the passed value to the passed key.
 *
 * @param[in]  key  A ractor-local storage key.
 * @param[in]  val  Arbitrary ruby object.
 * @post       `val` corresponds to `key` in the current Ractor.
 */
void  rb_ractor_local_storage_value_set(rb_ractor_local_key_t key, VALUE val);

/**
 * A type of ractor-local storage that destructs itself using ::ruby_xfree.
 *
 * @internal
 *
 * Why  it is  visible from  3rd party  extension libraries  is not  obvious to
 * @shyouhei.
 */
RUBY_EXTERN const struct rb_ractor_local_storage_type rb_ractor_local_storage_type_free;

/** @alias{rb_ractor_local_storage_type_free} */
#define RB_RACTOR_LOCAL_STORAGE_TYPE_FREE (&rb_ractor_local_storage_type_free)

/**
 * Extended version of rb_ractor_local_storage_value_newkey().  It additionally
 * takes the type of the issuing key.
 *
 * @param[in]  type  How  the  value associated  with  the  issuing key  should
 *                   behave.
 * @return     A newly issued ractor-local storage key, of type `type`.
 */
rb_ractor_local_key_t rb_ractor_local_storage_ptr_newkey(const struct rb_ractor_local_storage_type *type);

/**
 * Identical to rb_ractor_local_storage_value() except the return type.
 *
 * @param[in]  key        A ractor-local storage key to lookup.
 * @retval     NULL       No such key.
 * @retval     otherwise  A value corresponds to `key` in the current Ractor.
 */
void *rb_ractor_local_storage_ptr(rb_ractor_local_key_t key);

/**
 * Identical to rb_ractor_local_storage_value_set() except the parameter type.
 *
 * @param[in]  key  A ractor-local storage key.
 * @param[in]  ptr  A pointer that conforms `key`'s type.
 * @post       `ptr` corresponds to `key` in the current Ractor.
 */
void  rb_ractor_local_storage_ptr_set(rb_ractor_local_key_t key, void *ptr);

/**
 * Destructively  transforms the  passed object  so that  multiple Ractors  can
 * share it.  What is a shareable object  and what is not is a nuanced concept,
 * and @ko1  says the definition  can still change.  However  extension library
 * authors might interest to learn how to use #RUBY_TYPED_FROZEN_SHAREABLE.
 *
 * @param[out]  obj              Arbitrary ruby object to modify.
 * @exception   rb_eRactorError  Ractors cannot share `obj` by nature.
 * @return      Passed `obj`.
 * @post        Multiple Ractors can share `obj`.
 *
 * @internal
 *
 * In case an exception is raised, `obj` remains in an intermediate state where
 * some of its part is frozen and others  are not.  @shyouhei is not sure if it
 * is  either  an intended  behaviour,  current  implementation limitation,  or
 * simply a bug.  Note also that there is no way to "melt" a frozen object.
 */
VALUE rb_ractor_make_shareable(VALUE obj);

/**
 * Identical to rb_ractor_make_shareable(), except it  returns a (deep) copy of
 * the passed one instead of modifying it in-place.
 *
 * @param[in]   obj              Arbitrary ruby object to duplicate.
 * @exception   rb_eRactorError  Ractors cannot share `obj` by nature.
 * @return      A deep copy of `obj` which is sharable among Ractors.
 */
VALUE rb_ractor_make_shareable_copy(VALUE obj);

RBIMPL_SYMBOL_EXPORT_END()

/**
 * Queries if the passed object has  previously classified as shareable or not.
 * This  doesn't mean  anything in  practice...  Objects  can be  shared later.
 * Always use rb_ractor_shareable_p() instead.
 *
 * @param[in]  obj                Object in question.
 * @retval     RUBY_FL_SHAREABLE  It once was shareable before.
 * @retval     0                  Otherwise.
 */
#define RB_OBJ_SHAREABLE_P(obj) FL_TEST_RAW((obj), RUBY_FL_SHAREABLE)

/**
 * Queries if multiple Ractors can share the passed object or not.  Ractors run
 * without protecting  each other.  Sharing  an object among them  is basically
 * dangerous,  disabled  by  default.   However  there  are  objects  that  are
 * extremely  carefully implemented  to be  Ractor-safe; for  instance integers
 * have such property.  This function can classify that.
 *
 * @param[in]   obj    Arbitrary ruby object.
 * @retval      true   `obj` is capable of shared across ractors.
 * @retval      false  `obj` cannot travel across ractor boundaries.
 */
static inline bool
rb_ractor_shareable_p(VALUE obj)
{
    bool rb_ractor_shareable_p_continue(VALUE obj);

    if (RB_SPECIAL_CONST_P(obj)) {
        return true;
    }
    else if (RB_OBJ_SHAREABLE_P(obj)) {
        return true;
    }
    else {
        return rb_ractor_shareable_p_continue(obj);
    }
}

#endif /* RUBY_RACTOR_H */
