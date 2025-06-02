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
#ifndef MSGPACK_RUBY_UNPACKER_EXT_REGISTRY_H__
#define MSGPACK_RUBY_UNPACKER_EXT_REGISTRY_H__

#include "compat.h"
#include "ruby.h"

#define MSGPACK_EXT_RECURSIVE 0b0001

struct msgpack_unpacker_ext_registry_t;
typedef struct msgpack_unpacker_ext_registry_t msgpack_unpacker_ext_registry_t;

struct msgpack_unpacker_ext_registry_t {
    unsigned int borrow_count;
    VALUE array[256];
};

void msgpack_unpacker_ext_registry_release(msgpack_unpacker_ext_registry_t* ukrg);

static inline void msgpack_unpacker_ext_registry_borrow(msgpack_unpacker_ext_registry_t* src, msgpack_unpacker_ext_registry_t** dst)
{
    if (src) {
        src->borrow_count++;
        *dst = src;
    }
}

void msgpack_unpacker_ext_registry_mark(msgpack_unpacker_ext_registry_t* ukrg);

void msgpack_unpacker_ext_registry_put(VALUE owner, msgpack_unpacker_ext_registry_t** ukrg,
        VALUE ext_module, int ext_type, int flags, VALUE proc);

static inline VALUE msgpack_unpacker_ext_registry_lookup(msgpack_unpacker_ext_registry_t* ukrg,
        int ext_type, int* ext_flags_result)
{
    if (ukrg) {
        VALUE entry = ukrg->array[ext_type + 128];
        if (entry != Qnil) {
            *ext_flags_result = FIX2INT(rb_ary_entry(entry, 2));
            return rb_ary_entry(entry, 1);
        }
    }
    return Qnil;
}

#endif
