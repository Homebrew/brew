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

#include "packer_ext_registry.h"

void msgpack_packer_ext_registry_init(VALUE owner, msgpack_packer_ext_registry_t* pkrg)
{
    RB_OBJ_WRITE(owner, &pkrg->hash, Qnil);
    RB_OBJ_WRITE(owner, &pkrg->cache, Qnil);
}

void msgpack_packer_ext_registry_mark(msgpack_packer_ext_registry_t* pkrg)
{
    rb_gc_mark(pkrg->hash);
    rb_gc_mark(pkrg->cache);
}

void msgpack_packer_ext_registry_borrow(VALUE owner, msgpack_packer_ext_registry_t* src,
        msgpack_packer_ext_registry_t* dst)
{
    if(RTEST(src->hash)) {
        if(rb_obj_frozen_p(src->hash)) {
            // If the type registry is frozen we can safely share it, and share the cache as well.
            RB_OBJ_WRITE(owner, &dst->hash, src->hash);
            RB_OBJ_WRITE(owner, &dst->cache, src->cache);
        } else {
            RB_OBJ_WRITE(owner, &dst->hash, rb_hash_dup(src->hash));
            RB_OBJ_WRITE(owner, &dst->cache, NIL_P(src->cache) ? Qnil : rb_hash_dup(src->cache));
        }
    } else {
        RB_OBJ_WRITE(owner, &dst->hash, Qnil);
        RB_OBJ_WRITE(owner, &dst->cache, Qnil);
    }
}

void msgpack_packer_ext_registry_dup(VALUE owner, msgpack_packer_ext_registry_t* src,
        msgpack_packer_ext_registry_t* dst)
{
    RB_OBJ_WRITE(owner, &dst->hash, NIL_P(src->hash) ? Qnil : rb_hash_dup(src->hash));
    RB_OBJ_WRITE(owner, &dst->cache, NIL_P(src->cache) ? Qnil : rb_hash_dup(src->cache));
}

void msgpack_packer_ext_registry_put(VALUE owner, msgpack_packer_ext_registry_t* pkrg,
        VALUE ext_module, int ext_type, int flags, VALUE proc)
{
    if(NIL_P(pkrg->hash)) {
        RB_OBJ_WRITE(owner, &pkrg->hash, rb_hash_new());
    }

    if(NIL_P(pkrg->cache)) {
        RB_OBJ_WRITE(owner, &pkrg->cache, rb_hash_new());
    } else {
        /* clear lookup cache not to miss added type */
        rb_hash_clear(pkrg->cache);
    }

    VALUE entry = rb_ary_new3(3, INT2FIX(ext_type), proc, INT2FIX(flags));
    rb_hash_aset(pkrg->hash, ext_module, entry);
}
