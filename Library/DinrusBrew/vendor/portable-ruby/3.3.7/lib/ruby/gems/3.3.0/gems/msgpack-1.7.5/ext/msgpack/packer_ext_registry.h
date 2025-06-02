/*
 * MessagePack for Ruby
 *
 * Copyright (C) 2008-2015 Sadayuki Furuhashi
 *
 *    Licensed under the Apache License, Version 2.0 (the "License");
 *    you may not use this file except in compliance with the License.
 *    You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 *    Unless required by applicable law or agreed to in writing, software
 *    distributed under the License is distributed on an "AS IS" BASIS,
 *    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *    See the License for the specific language governing permissions and
 *    limitations under the License.
 */
#ifndef MSGPACK_RUBY_PACKER_EXT_REGISTRY_H__
#define MSGPACK_RUBY_PACKER_EXT_REGISTRY_H__

#include "compat.h"
#include "ruby.h"

#define MSGPACK_EXT_RECURSIVE 0b0001

struct msgpack_packer_ext_registry_t;
typedef struct msgpack_packer_ext_registry_t msgpack_packer_ext_registry_t;

struct msgpack_packer_ext_registry_t {
    VALUE hash;
    VALUE cache; // lookup cache for ext types inherited from a super class
};

void msgpack_packer_ext_registry_init(VALUE owner, msgpack_packer_ext_registry_t* pkrg);

static inline void msgpack_packer_ext_registry_destroy(msgpack_packer_ext_registry_t* pkrg)
{ }

void msgpack_packer_ext_registry_mark(msgpack_packer_ext_registry_t* pkrg);

void msgpack_packer_ext_registry_borrow(VALUE owner, msgpack_packer_ext_registry_t* src,
        msgpack_packer_ext_registry_t* dst);

void msgpack_packer_ext_registry_dup(VALUE owner, msgpack_packer_ext_registry_t* src,
        msgpack_packer_ext_registry_t* dst);

void msgpack_packer_ext_registry_put(VALUE owner, msgpack_packer_ext_registry_t* pkrg,
        VALUE ext_module, int ext_type, int flags, VALUE proc);

static int msgpack_packer_ext_find_superclass(VALUE key, VALUE value, VALUE arg)
{
    VALUE *args = (VALUE *) arg;
    if(key == Qundef) {
        return ST_CONTINUE;
    }
    if(rb_class_inherited_p(args[0], key) == Qtrue) {
        args[1] = key;
        return ST_STOP;
    }
    return ST_CONTINUE;
}

static inline VALUE msgpack_packer_ext_registry_fetch(msgpack_packer_ext_registry_t* pkrg,
        VALUE lookup_class, int* ext_type_result, int* ext_flags_result)
{
    // fetch lookup_class from hash, which is a hash to register classes
    VALUE type = rb_hash_lookup(pkrg->hash, lookup_class);
    if(type != Qnil) {
        *ext_type_result = FIX2INT(rb_ary_entry(type, 0));
        *ext_flags_result = FIX2INT(rb_ary_entry(type, 2));
        return rb_ary_entry(type, 1);
    }

    // fetch lookup_class from cache, which stores results of searching ancestors from pkrg->hash
    if (RTEST(pkrg->cache)) {
        VALUE type_inht = rb_hash_lookup(pkrg->cache, lookup_class);
        if(type_inht != Qnil) {
            *ext_type_result = FIX2INT(rb_ary_entry(type_inht, 0));
            *ext_flags_result = FIX2INT(rb_ary_entry(type_inht, 2));
            return rb_ary_entry(type_inht, 1);
        }
    }

    return Qnil;
}

static inline VALUE msgpack_packer_ext_registry_lookup(msgpack_packer_ext_registry_t* pkrg,
        VALUE instance, int* ext_type_result, int* ext_flags_result)
{
    VALUE type;

    if (pkrg->hash == Qnil) { // No extensions registered
        return Qnil;
    }

   /*
    * 1. check whether singleton_class or class of this instance is registered (or resolved in past) or not.
    *
    * Objects of type Integer (Fixnum, Bignum), Float, Symbol and frozen
    * `rb_class_of` returns the singleton_class if the object has one, or the "real class" otherwise.
    */
    VALUE lookup_class = rb_class_of(instance);
    type = msgpack_packer_ext_registry_fetch(pkrg, lookup_class, ext_type_result, ext_flags_result);
    if(type != Qnil) {
        return type;
    }

    /*
     * 2. If the object had a singleton_class check if the real class of instance is registered
     * (or resolved in past) or not.
     */
    VALUE real_class = rb_obj_class(instance);
    if(lookup_class != real_class) {
        type = msgpack_packer_ext_registry_fetch(pkrg, real_class, ext_type_result, ext_flags_result);
        if(type != Qnil) {
            return type;
        }
    }

    /*
     * 3. check all keys whether it is an ancestor of lookup_class, or not
     */
    VALUE args[2];
    args[0] = lookup_class;
    args[1] = Qnil;
    rb_hash_foreach(pkrg->hash, msgpack_packer_ext_find_superclass, (VALUE) args);

    VALUE superclass = args[1];
    if(superclass != Qnil) {
        VALUE superclass_type = rb_hash_lookup(pkrg->hash, superclass);
        rb_hash_aset(pkrg->cache, lookup_class, superclass_type);
        *ext_type_result = FIX2INT(rb_ary_entry(superclass_type, 0));
        *ext_flags_result = FIX2INT(rb_ary_entry(superclass_type, 2));
        return rb_ary_entry(superclass_type, 1);
    }

    return Qnil;
}

#endif
