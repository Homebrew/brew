/*
 * MessagePack for Ruby
 *
 * Copyright (C) 2008-2013 Sadayuki Furuhashi
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

#include "packer.h"
#include "buffer_class.h"

#if !defined(HAVE_RB_PROC_CALL_WITH_BLOCK)
#define rb_proc_call_with_block(recv, argc, argv, block) rb_funcallv(recv, rb_intern("call"), argc, argv)
#endif

void msgpack_packer_init(msgpack_packer_t* pk)
{
    msgpack_buffer_init(PACKER_BUFFER_(pk));
}

void msgpack_packer_destroy(msgpack_packer_t* pk)
{
    msgpack_buffer_destroy(PACKER_BUFFER_(pk));
}

void msgpack_packer_mark(msgpack_packer_t* pk)
{
    /* See MessagePack_Buffer_wrap */
    /* msgpack_buffer_mark(PACKER_BUFFER_(pk)); */
    rb_gc_mark(pk->buffer_ref);
    rb_gc_mark(pk->to_msgpack_arg);
}

void msgpack_packer_reset(msgpack_packer_t* pk)
{
    msgpack_buffer_clear(PACKER_BUFFER_(pk));

    pk->buffer_ref = Qnil;
}


void msgpack_packer_write_array_value(msgpack_packer_t* pk, VALUE v)
{
    /* actual return type of RARRAY_LEN is long */
    unsigned long len = RARRAY_LEN(v);
    if(len > 0xffffffffUL) {
        rb_raise(rb_eArgError, "size of array is too long to pack: %lu bytes should be <= %lu", len, 0xffffffffUL);
    }
    unsigned int len32 = (unsigned int)len;
    msgpack_packer_write_array_header(pk, len32);

    unsigned int i;
    for(i=0; i < len32; ++i) {
        VALUE e = rb_ary_entry(v, i);
        msgpack_packer_write_value(pk, e);
    }
}

static int write_hash_foreach(VALUE key, VALUE value, VALUE pk_value)
{
    if (key == Qundef) {
        return ST_CONTINUE;
    }
    msgpack_packer_t* pk = (msgpack_packer_t*) pk_value;
    msgpack_packer_write_value(pk, key);
    msgpack_packer_write_value(pk, value);
    return ST_CONTINUE;
}

void msgpack_packer_write_hash_value(msgpack_packer_t* pk, VALUE v)
{
    /* actual return type of RHASH_SIZE is long (if SIZEOF_LONG == SIZEOF_VOIDP
     * or long long (if SIZEOF_LONG_LONG == SIZEOF_VOIDP. See st.h. */
    unsigned long len = RHASH_SIZE(v);
    if(len > 0xffffffffUL) {
        rb_raise(rb_eArgError, "size of array is too long to pack: %ld bytes should be <= %lu", len, 0xffffffffUL);
    }
    unsigned int len32 = (unsigned int)len;
    msgpack_packer_write_map_header(pk, len32);

    rb_hash_foreach(v, write_hash_foreach, (VALUE) pk);
}

struct msgpack_call_proc_args_t;
typedef struct msgpack_call_proc_args_t msgpack_call_proc_args_t;
struct msgpack_call_proc_args_t {
    VALUE proc;
    VALUE args[2];
};

VALUE msgpack_packer_try_calling_proc(VALUE value)
{
    msgpack_call_proc_args_t *args = (msgpack_call_proc_args_t *)value;
    return rb_proc_call_with_block(args->proc, 2, args->args, Qnil);
}

bool msgpack_packer_try_write_with_ext_type_lookup(msgpack_packer_t* pk, VALUE v)
{
    int ext_type, ext_flags;

    VALUE proc = msgpack_packer_ext_registry_lookup(&pk->ext_registry, v, &ext_type, &ext_flags);

    if(proc == Qnil) {
        return false;
    }

    if(ext_flags & MSGPACK_EXT_RECURSIVE) {
        VALUE held_buffer = MessagePack_Buffer_hold(&pk->buffer);

        msgpack_buffer_t parent_buffer = pk->buffer;
        msgpack_buffer_init(PACKER_BUFFER_(pk));

        int exception_occured = 0;
        msgpack_call_proc_args_t args = { proc, { v, pk->to_msgpack_arg } };
        rb_protect(msgpack_packer_try_calling_proc, (VALUE)&args, &exception_occured);

        if (exception_occured) {
            msgpack_buffer_destroy(PACKER_BUFFER_(pk));
            pk->buffer = parent_buffer;
            rb_jump_tag(exception_occured); // re-raise the exception
        } else {
            VALUE payload = msgpack_buffer_all_as_string(PACKER_BUFFER_(pk));
            StringValue(payload);
            msgpack_buffer_destroy(PACKER_BUFFER_(pk));
            pk->buffer = parent_buffer;
            msgpack_packer_write_ext(pk, ext_type, payload);
        }

        RB_GC_GUARD(held_buffer);
    } else {
        VALUE payload = rb_proc_call_with_block(proc, 1, &v, Qnil);
        StringValue(payload);
        msgpack_packer_write_ext(pk, ext_type, payload);
    }

    return true;
}

void msgpack_packer_write_other_value(msgpack_packer_t* pk, VALUE v)
{
    if(!(msgpack_packer_try_write_with_ext_type_lookup(pk, v))) {
        rb_funcall(v, pk->to_msgpack_method, 1, pk->to_msgpack_arg);
    }
}

void msgpack_packer_write_value(msgpack_packer_t* pk, VALUE v)
{
    switch(rb_type(v)) {
    case T_NIL:
        msgpack_packer_write_nil(pk);
        break;
    case T_TRUE:
        msgpack_packer_write_true(pk);
        break;
    case T_FALSE:
        msgpack_packer_write_false(pk);
        break;
    case T_FIXNUM:
        msgpack_packer_write_fixnum_value(pk, v);
        break;
    case T_SYMBOL:
        msgpack_packer_write_symbol_value(pk, v);
        break;
    case T_STRING:
        if(rb_class_of(v) == rb_cString || !msgpack_packer_try_write_with_ext_type_lookup(pk, v)) {
            msgpack_packer_write_string_value(pk, v);
        }
        break;
    case T_ARRAY:
        if(rb_class_of(v) == rb_cArray || !msgpack_packer_try_write_with_ext_type_lookup(pk, v)) {
            msgpack_packer_write_array_value(pk, v);
        }
        break;
    case T_HASH:
        if(rb_class_of(v) == rb_cHash || !msgpack_packer_try_write_with_ext_type_lookup(pk, v)) {
            msgpack_packer_write_hash_value(pk, v);
        }
        break;
    case T_BIGNUM:
        msgpack_packer_write_bignum_value(pk, v);
        break;
    case T_FLOAT:
        msgpack_packer_write_float_value(pk, v);
        break;
    default:
        msgpack_packer_write_other_value(pk, v);
    }
}

