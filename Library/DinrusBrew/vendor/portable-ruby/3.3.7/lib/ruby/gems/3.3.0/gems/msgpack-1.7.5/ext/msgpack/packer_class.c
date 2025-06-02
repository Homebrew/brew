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

#include "compat.h"
#include "ruby.h"
#include "packer.h"
#include "packer_class.h"
#include "buffer_class.h"
#include "factory_class.h"

VALUE cMessagePack_Packer;

static ID s_to_msgpack;
static ID s_write;

static VALUE sym_compatibility_mode;

//static VALUE s_packer_value;
//static msgpack_packer_t* s_packer;

static void Packer_free(void *ptr)
{
    msgpack_packer_t* pk = ptr;
    if(pk == NULL) {
        return;
    }
    msgpack_packer_ext_registry_destroy(&pk->ext_registry);
    msgpack_packer_destroy(pk);
    xfree(pk);
}

static void Packer_mark(void *ptr)
{
    msgpack_packer_t* pk = ptr;
    msgpack_buffer_mark(pk);
    msgpack_packer_mark(pk);
    msgpack_packer_ext_registry_mark(&pk->ext_registry);
}

static size_t Packer_memsize(const void *ptr)
{
    const msgpack_packer_t* pk = ptr;
    return sizeof(msgpack_packer_t) + msgpack_buffer_memsize(&pk->buffer);
}

const rb_data_type_t packer_data_type = {
    .wrap_struct_name = "msgpack:packer",
    .function = {
        .dmark = Packer_mark,
        .dfree = Packer_free,
        .dsize = Packer_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY
};


VALUE MessagePack_Packer_alloc(VALUE klass)
{
    msgpack_packer_t* pk;
    VALUE self = TypedData_Make_Struct(klass, msgpack_packer_t, &packer_data_type, pk);
    msgpack_packer_init(pk);
    msgpack_packer_set_to_msgpack_method(pk, s_to_msgpack, self);
    return self;
}

VALUE MessagePack_Packer_initialize(int argc, VALUE* argv, VALUE self)
{
    if(argc > 2) {
        rb_raise(rb_eArgError, "wrong number of arguments (%d for 0..2)", argc);
    }

    VALUE io = Qnil;
    VALUE options = Qnil;

    if(argc >= 1) {
        io = argv[0];
    }

    if(argc == 2) {
        options = argv[1];
    }

    if (options == Qnil && rb_type(io) == T_HASH) {
        options = io;
        io = Qnil;
    }

    if(options != Qnil) {
        Check_Type(options, T_HASH);
    }

    msgpack_packer_t *pk = MessagePack_Packer_get(self);

    msgpack_packer_ext_registry_init(self, &pk->ext_registry);
    pk->buffer_ref = MessagePack_Buffer_wrap(PACKER_BUFFER_(pk), self);

    MessagePack_Buffer_set_options(PACKER_BUFFER_(pk), io, options);

    if(options != Qnil) {
        VALUE v;

        v = rb_hash_aref(options, sym_compatibility_mode);
        msgpack_packer_set_compat(pk, RTEST(v));
    }

    return self;
}

static VALUE Packer_compatibility_mode_p(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    return pk->compatibility_mode ? Qtrue : Qfalse;
}

static VALUE Packer_buffer(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    if (!RTEST(pk->buffer_ref)) {
        pk->buffer_ref = MessagePack_Buffer_wrap(PACKER_BUFFER_(pk), self);
    }
    return pk->buffer_ref;
}

static VALUE Packer_write(VALUE self, VALUE v)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_value(pk, v);
    return self;
}

static VALUE Packer_write_nil(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_nil(pk);
    return self;
}

static VALUE Packer_write_true(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_true(pk);
    return self;
}

static VALUE Packer_write_false(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_false(pk);
    return self;
}

static VALUE Packer_write_float(VALUE self, VALUE obj)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_float_value(pk, obj);
    return self;
}

static VALUE Packer_write_string(VALUE self, VALUE obj)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    Check_Type(obj, T_STRING);
    msgpack_packer_write_string_value(pk, obj);
    return self;
}

static VALUE Packer_write_bin(VALUE self, VALUE obj)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    Check_Type(obj, T_STRING);

    VALUE enc = rb_enc_from_encoding(rb_ascii8bit_encoding());
    obj = rb_str_encode(obj, enc, 0, Qnil);

    msgpack_packer_write_string_value(pk, obj);
    return self;
}

static VALUE Packer_write_array(VALUE self, VALUE obj)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    Check_Type(obj, T_ARRAY);
    msgpack_packer_write_array_value(pk, obj);
    return self;
}

static VALUE Packer_write_hash(VALUE self, VALUE obj)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    Check_Type(obj, T_HASH);
    msgpack_packer_write_hash_value(pk, obj);
    return self;
}

static VALUE Packer_write_symbol(VALUE self, VALUE obj)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    Check_Type(obj, T_SYMBOL);
    msgpack_packer_write_symbol_value(pk, obj);
    return self;
}

static VALUE Packer_write_int(VALUE self, VALUE obj)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);

    if (FIXNUM_P(obj)) {
        msgpack_packer_write_fixnum_value(pk, obj);
    } else {
        Check_Type(obj, T_BIGNUM);
        msgpack_packer_write_bignum_value(pk, obj);
    }
    return self;
}

static VALUE Packer_write_extension(VALUE self, VALUE obj)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    Check_Type(obj, T_STRUCT);

    VALUE rb_ext_type = RSTRUCT_GET(obj, 0);
    if(!RB_TYPE_P(rb_ext_type, T_FIXNUM)) {
        rb_raise(rb_eRangeError, "integer %s too big to convert to `signed char'", RSTRING_PTR(rb_String(rb_ext_type)));
    }

    int ext_type = FIX2INT(rb_ext_type);
    if(ext_type < -128 || ext_type > 127) {
        rb_raise(rb_eRangeError, "integer %d too big to convert to `signed char'", ext_type);
    }
    VALUE payload = RSTRUCT_GET(obj, 1);
    StringValue(payload);
    msgpack_packer_write_ext(pk, ext_type, payload);

    return self;
}

static VALUE Packer_write_array_header(VALUE self, VALUE n)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_array_header(pk, NUM2UINT(n));
    return self;
}

static VALUE Packer_write_map_header(VALUE self, VALUE n)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_map_header(pk, NUM2UINT(n));
    return self;
}

static VALUE Packer_write_bin_header(VALUE self, VALUE n)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_bin_header(pk, NUM2UINT(n));
    return self;
}

static VALUE Packer_write_float32(VALUE self, VALUE numeric)
{
    if(!rb_obj_is_kind_of(numeric, rb_cNumeric)) {
      rb_raise(rb_eArgError, "Expected numeric");
    }

    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_packer_write_float(pk, (float)rb_num2dbl(numeric));
    return self;
}

static VALUE Packer_write_ext(VALUE self, VALUE type, VALUE data)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    int ext_type = NUM2INT(type);
    if(ext_type < -128 || ext_type > 127) {
        rb_raise(rb_eRangeError, "integer %d too big to convert to `signed char'", ext_type);
    }
    StringValue(data);
    msgpack_packer_write_ext(pk, ext_type, data);
    return self;
}

static VALUE Packer_flush(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_buffer_flush(PACKER_BUFFER_(pk));
    return self;
}

static VALUE Packer_reset(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    msgpack_buffer_clear(PACKER_BUFFER_(pk));
    return Qnil;
}

static VALUE Packer_size(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    size_t size = msgpack_buffer_all_readable_size(PACKER_BUFFER_(pk));
    return SIZET2NUM(size);
}

static VALUE Packer_empty_p(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    if(msgpack_buffer_top_readable_size(PACKER_BUFFER_(pk)) == 0) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

static VALUE Packer_to_str(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    return msgpack_buffer_all_as_string(PACKER_BUFFER_(pk));
}

static VALUE Packer_to_a(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    return msgpack_buffer_all_as_string_array(PACKER_BUFFER_(pk));
}

static VALUE Packer_write_to(VALUE self, VALUE io)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    size_t sz = msgpack_buffer_flush_to_io(PACKER_BUFFER_(pk), io, s_write, true);
    return SIZET2NUM(sz);
}

static VALUE Packer_registered_types_internal(VALUE self)
{
    msgpack_packer_t *pk = MessagePack_Packer_get(self);
    if (RTEST(pk->ext_registry.hash)) {
        return rb_hash_dup(pk->ext_registry.hash);
    }
    return rb_hash_new();
}

static VALUE Packer_register_type_internal(VALUE self, VALUE rb_ext_type, VALUE ext_module, VALUE proc)
{
    if (OBJ_FROZEN(self)) {
        rb_raise(rb_eFrozenError, "can't modify frozen MessagePack::Packer");
    }

    msgpack_packer_t *pk = MessagePack_Packer_get(self);

    int ext_type = NUM2INT(rb_ext_type);
    if(ext_type < -128 || ext_type > 127) {
        rb_raise(rb_eRangeError, "integer %d too big to convert to `signed char'", ext_type);
    }

    msgpack_packer_ext_registry_put(self, &pk->ext_registry, ext_module, ext_type, 0, proc);

    if (ext_module == rb_cSymbol) {
        pk->has_symbol_ext_type = true;
    }

    return Qnil;
}

VALUE Packer_full_pack(VALUE self)
{
    VALUE retval;

    msgpack_packer_t *pk = MessagePack_Packer_get(self);

    if(msgpack_buffer_has_io(PACKER_BUFFER_(pk))) {
        msgpack_buffer_flush(PACKER_BUFFER_(pk));
        retval = Qnil;
    } else {
        retval = msgpack_buffer_all_as_string(PACKER_BUFFER_(pk));
    }

    msgpack_buffer_clear(PACKER_BUFFER_(pk)); /* to free rmem before GC */

    return retval;
}

void MessagePack_Packer_module_init(VALUE mMessagePack)
{
    s_to_msgpack = rb_intern("to_msgpack");
    s_write = rb_intern("write");

    sym_compatibility_mode = ID2SYM(rb_intern("compatibility_mode"));
    cMessagePack_Packer = rb_define_class_under(mMessagePack, "Packer", rb_cObject);

    rb_define_alloc_func(cMessagePack_Packer, MessagePack_Packer_alloc);

    rb_define_method(cMessagePack_Packer, "initialize", MessagePack_Packer_initialize, -1);
    rb_define_method(cMessagePack_Packer, "compatibility_mode?", Packer_compatibility_mode_p, 0);
    rb_define_method(cMessagePack_Packer, "buffer", Packer_buffer, 0);
    rb_define_method(cMessagePack_Packer, "write", Packer_write, 1);
    rb_define_alias(cMessagePack_Packer, "pack", "write");
    rb_define_method(cMessagePack_Packer, "write_nil", Packer_write_nil, 0);
    rb_define_method(cMessagePack_Packer, "write_true", Packer_write_true, 0);
    rb_define_method(cMessagePack_Packer, "write_false", Packer_write_false, 0);
    rb_define_method(cMessagePack_Packer, "write_float", Packer_write_float, 1);
    rb_define_method(cMessagePack_Packer, "write_string", Packer_write_string, 1);
    rb_define_method(cMessagePack_Packer, "write_bin", Packer_write_bin, 1);
    rb_define_method(cMessagePack_Packer, "write_array", Packer_write_array, 1);
    rb_define_method(cMessagePack_Packer, "write_hash", Packer_write_hash, 1);
    rb_define_method(cMessagePack_Packer, "write_symbol", Packer_write_symbol, 1);
    rb_define_method(cMessagePack_Packer, "write_int", Packer_write_int, 1);
    rb_define_method(cMessagePack_Packer, "write_extension", Packer_write_extension, 1);
    rb_define_method(cMessagePack_Packer, "write_array_header", Packer_write_array_header, 1);
    rb_define_method(cMessagePack_Packer, "write_map_header", Packer_write_map_header, 1);
    rb_define_method(cMessagePack_Packer, "write_bin_header", Packer_write_bin_header, 1);
    rb_define_method(cMessagePack_Packer, "write_ext", Packer_write_ext, 2);
    rb_define_method(cMessagePack_Packer, "write_float32", Packer_write_float32, 1);
    rb_define_method(cMessagePack_Packer, "flush", Packer_flush, 0);

    /* delegation methods */
    rb_define_method(cMessagePack_Packer, "reset", Packer_reset, 0);
    rb_define_alias(cMessagePack_Packer, "clear", "reset");
    rb_define_method(cMessagePack_Packer, "size", Packer_size, 0);
    rb_define_method(cMessagePack_Packer, "empty?", Packer_empty_p, 0);
    rb_define_method(cMessagePack_Packer, "write_to", Packer_write_to, 1);
    rb_define_method(cMessagePack_Packer, "to_str", Packer_to_str, 0);
    rb_define_alias(cMessagePack_Packer, "to_s", "to_str");
    rb_define_method(cMessagePack_Packer, "to_a", Packer_to_a, 0);

    rb_define_private_method(cMessagePack_Packer, "registered_types_internal", Packer_registered_types_internal, 0);
    rb_define_method(cMessagePack_Packer, "register_type_internal", Packer_register_type_internal, 3);

    rb_define_method(cMessagePack_Packer, "full_pack", Packer_full_pack, 0);
}
