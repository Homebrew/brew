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

#include "unpacker.h"
#include "unpacker_class.h"
#include "buffer_class.h"
#include "factory_class.h"

VALUE cMessagePack_Unpacker;

//static VALUE s_unpacker_value;
//static msgpack_unpacker_t* s_unpacker;

static VALUE eUnpackError;
static VALUE eMalformedFormatError;
static VALUE eStackError;
static VALUE eUnexpectedTypeError;
static VALUE eUnknownExtTypeError;
static VALUE mTypeError;  // obsoleted. only for backward compatibility. See #86.

static VALUE sym_symbolize_keys;
static VALUE sym_freeze;
static VALUE sym_allow_unknown_ext;

static void Unpacker_free(void *ptr)
{
    msgpack_unpacker_t* uk = ptr;
    if(uk == NULL) {
        return;
    }
    msgpack_unpacker_ext_registry_release(uk->ext_registry);
    _msgpack_unpacker_destroy(uk);
    xfree(uk);
}

static void Unpacker_mark(void *ptr)
{
    msgpack_unpacker_t* uk = ptr;
    msgpack_buffer_mark(uk);
    msgpack_unpacker_mark(uk);
    msgpack_unpacker_ext_registry_mark(uk->ext_registry);
}

static size_t Unpacker_memsize(const void *ptr)
{
    const msgpack_unpacker_t* uk = ptr;

    size_t total_size = sizeof(msgpack_unpacker_t);

    if (uk->ext_registry) {
        total_size += sizeof(msgpack_unpacker_ext_registry_t) / (uk->ext_registry->borrow_count + 1);
    }

    if (uk->stack.data) {
        total_size += (uk->stack.depth + 1) * sizeof(msgpack_unpacker_stack_t);
    }

    return total_size + msgpack_buffer_memsize(&uk->buffer);
}

const rb_data_type_t unpacker_data_type = {
    .wrap_struct_name = "msgpack:unpacker",
    .function = {
        .dmark = Unpacker_mark,
        .dfree = Unpacker_free,
        .dsize = Unpacker_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

VALUE MessagePack_Unpacker_alloc(VALUE klass)
{
    msgpack_unpacker_t* uk;
    VALUE self = TypedData_Make_Struct(klass, msgpack_unpacker_t, &unpacker_data_type, uk);
    _msgpack_unpacker_init(uk);
    uk->self = self;
    return self;
}

VALUE MessagePack_Unpacker_initialize(int argc, VALUE* argv, VALUE self)
{
    VALUE io = Qnil;
    VALUE options = Qnil;

    if(argc == 0 || (argc == 1 && argv[0] == Qnil)) {
        /* Qnil */

    } else if(argc == 1) {
        VALUE v = argv[0];
        if(rb_type(v) == T_HASH) {
            options = v;
        } else {
            io = v;
        }

    } else if(argc == 2) {
        io = argv[0];
        options = argv[1];
        if(options != Qnil && rb_type(options) != T_HASH) {
            rb_raise(rb_eArgError, "expected Hash but found %s.", rb_obj_classname(options));
        }

    } else {
        rb_raise(rb_eArgError, "wrong number of arguments (%d for 0..2)", argc);
    }

    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    uk->buffer_ref = Qnil;

    MessagePack_Buffer_set_options(UNPACKER_BUFFER_(uk), io, options);

    if(options != Qnil) {
        VALUE v;

        v = rb_hash_aref(options, sym_symbolize_keys);
        msgpack_unpacker_set_symbolized_keys(uk, RTEST(v));

        v = rb_hash_aref(options, sym_freeze);
        msgpack_unpacker_set_freeze(uk, RTEST(v));

        v = rb_hash_aref(options, sym_allow_unknown_ext);
        msgpack_unpacker_set_allow_unknown_ext(uk, RTEST(v));
    }

    return self;
}

static VALUE Unpacker_symbolized_keys_p(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);
    return uk->symbolize_keys ? Qtrue : Qfalse;
}

static VALUE Unpacker_freeze_p(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);
    return uk->freeze ? Qtrue : Qfalse;
}

static VALUE Unpacker_allow_unknown_ext_p(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);
    return uk->allow_unknown_ext ? Qtrue : Qfalse;
}

NORETURN(static void raise_unpacker_error(msgpack_unpacker_t *uk, int r))
{
    uk->stack.depth = 0;
    switch(r) {
    case PRIMITIVE_EOF:
        rb_raise(rb_eEOFError, "end of buffer reached");
        break;
    case PRIMITIVE_INVALID_BYTE:
        rb_raise(eMalformedFormatError, "invalid byte");
        break;
    case PRIMITIVE_STACK_TOO_DEEP:
        rb_raise(eStackError, "stack level too deep");
        break;
    case PRIMITIVE_UNEXPECTED_TYPE:
        rb_raise(eUnexpectedTypeError, "unexpected type");
        break;
    case PRIMITIVE_UNEXPECTED_EXT_TYPE:
        rb_raise(eUnknownExtTypeError, "unexpected extension type");
        break;
    case PRIMITIVE_RECURSIVE_RAISED:
        rb_exc_raise(msgpack_unpacker_get_last_object(uk));
        break;
    default:
        rb_raise(eUnpackError, "logically unknown error %d", r);
    }
}

static VALUE Unpacker_buffer(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);
    if (!RTEST(uk->buffer_ref)) {
        uk->buffer_ref = MessagePack_Buffer_wrap(UNPACKER_BUFFER_(uk), self);
    }
    return uk->buffer_ref;
}

static VALUE Unpacker_read(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    int r = msgpack_unpacker_read(uk, 0);
    if(r < 0) {
        raise_unpacker_error(uk, r);
    }

    return msgpack_unpacker_get_last_object(uk);
}

static VALUE Unpacker_skip(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    int r = msgpack_unpacker_skip(uk, 0);
    if(r < 0) {
        raise_unpacker_error(uk, r);
    }

    return Qnil;
}

static VALUE Unpacker_skip_nil(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    int r = msgpack_unpacker_skip_nil(uk);
    if(r < 0) {
        raise_unpacker_error(uk, r);
    }

    if(r) {
        return Qtrue;
    }
    return Qfalse;
}

static VALUE Unpacker_read_array_header(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    uint32_t size;
    int r = msgpack_unpacker_read_array_header(uk, &size);
    if(r < 0) {
        raise_unpacker_error(uk, r);
    }

    return ULONG2NUM(size); // long at least 32 bits
}

static VALUE Unpacker_read_map_header(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    uint32_t size;
    int r = msgpack_unpacker_read_map_header(uk, &size);
    if(r < 0) {
        raise_unpacker_error(uk, r);
    }

    return ULONG2NUM(size); // long at least 32 bits
}

static VALUE Unpacker_feed_reference(VALUE self, VALUE data)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    StringValue(data);

    msgpack_buffer_append_string_reference(UNPACKER_BUFFER_(uk), data);

    return self;
}

static VALUE Unpacker_each_impl(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    while(true) {
        int r = msgpack_unpacker_read(uk, 0);
        if(r < 0) {
            if(r == PRIMITIVE_EOF) {
                return Qnil;
            }
            raise_unpacker_error(uk, r);
        }
        VALUE v = msgpack_unpacker_get_last_object(uk);
#ifdef JRUBY
        /* TODO JRuby's rb_yield behaves differently from Ruby 1.9.3 or Rubinius. */
        if(rb_type(v) == T_ARRAY) {
            v = rb_ary_new3(1, v);
        }
#endif
        rb_yield(v);
    }
}

static VALUE Unpacker_rescue_EOFError(VALUE args, VALUE error)
{
    UNUSED(args);
    UNUSED(error);
    return Qnil;
}

static VALUE Unpacker_each(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

#ifdef RETURN_ENUMERATOR
    RETURN_ENUMERATOR(self, 0, 0);
#endif

    if(msgpack_buffer_has_io(UNPACKER_BUFFER_(uk))) {
        /* rescue EOFError only if io is set */
        return rb_rescue2(Unpacker_each_impl, self,
                Unpacker_rescue_EOFError, self,
                rb_eEOFError, NULL);
    } else {
        return Unpacker_each_impl(self);
    }
}

static VALUE Unpacker_feed_each(VALUE self, VALUE data)
{
#ifdef RETURN_ENUMERATOR
    {
        VALUE argv[] = { data };
        RETURN_ENUMERATOR(self, sizeof(argv) / sizeof(VALUE), argv);
    }
#endif

    Unpacker_feed_reference(self, data);
    return Unpacker_each(self);
}

static VALUE Unpacker_reset(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    _msgpack_unpacker_reset(uk);

    return Qnil;
}

static VALUE Unpacker_registered_types_internal(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    VALUE mapping = rb_hash_new();
    if (uk->ext_registry) {
        for(int i=0; i < 256; i++) {
            if(uk->ext_registry->array[i] != Qnil) {
                rb_hash_aset(mapping, INT2FIX(i - 128), uk->ext_registry->array[i]);
            }
        }
    }

    return mapping;
}

static VALUE Unpacker_register_type_internal(VALUE self, VALUE rb_ext_type, VALUE ext_module, VALUE proc)
{
    if (OBJ_FROZEN(self)) {
        rb_raise(rb_eFrozenError, "can't modify frozen MessagePack::Unpacker");
    }

    int ext_type = NUM2INT(rb_ext_type);
    if(ext_type < -128 || ext_type > 127) {
        rb_raise(rb_eRangeError, "integer %d too big to convert to `signed char'", ext_type);
    }

    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);
    msgpack_unpacker_ext_registry_put(self, &uk->ext_registry, ext_module, ext_type, 0, proc);

    return Qnil;
}

static VALUE Unpacker_full_unpack(VALUE self)
{
    msgpack_unpacker_t *uk = MessagePack_Unpacker_get(self);

    int r = msgpack_unpacker_read(uk, 0);
    if(r < 0) {
        raise_unpacker_error(uk, r);
    }

    /* raise if extra bytes follow */
    size_t extra = msgpack_buffer_top_readable_size(UNPACKER_BUFFER_(uk));
    if(extra > 0) {
        rb_raise(eMalformedFormatError, "%zd extra bytes after the deserialized object", extra);
    }

    return msgpack_unpacker_get_last_object(uk);
}

VALUE MessagePack_Unpacker_new(int argc, VALUE* argv)
{
    VALUE self = MessagePack_Unpacker_alloc(cMessagePack_Unpacker);
    MessagePack_Unpacker_initialize(argc, argv, self);
    return self;
}

void MessagePack_Unpacker_module_init(VALUE mMessagePack)
{
    msgpack_unpacker_static_init();

    mTypeError = rb_define_module_under(mMessagePack, "TypeError");

    cMessagePack_Unpacker = rb_define_class_under(mMessagePack, "Unpacker", rb_cObject);

    eUnpackError = rb_define_class_under(mMessagePack, "UnpackError", rb_eStandardError);

    eMalformedFormatError = rb_define_class_under(mMessagePack, "MalformedFormatError", eUnpackError);

    eStackError = rb_define_class_under(mMessagePack, "StackError", eUnpackError);

    eUnexpectedTypeError = rb_define_class_under(mMessagePack, "UnexpectedTypeError", eUnpackError);
    rb_include_module(eUnexpectedTypeError, mTypeError);

    eUnknownExtTypeError = rb_define_class_under(mMessagePack, "UnknownExtTypeError", eUnpackError);

    sym_symbolize_keys = ID2SYM(rb_intern("symbolize_keys"));
    sym_freeze = ID2SYM(rb_intern("freeze"));
    sym_allow_unknown_ext = ID2SYM(rb_intern("allow_unknown_ext"));

    rb_define_alloc_func(cMessagePack_Unpacker, MessagePack_Unpacker_alloc);

    rb_define_method(cMessagePack_Unpacker, "initialize", MessagePack_Unpacker_initialize, -1);
    rb_define_method(cMessagePack_Unpacker, "symbolize_keys?", Unpacker_symbolized_keys_p, 0);
    rb_define_method(cMessagePack_Unpacker, "freeze?", Unpacker_freeze_p, 0);
    rb_define_method(cMessagePack_Unpacker, "allow_unknown_ext?", Unpacker_allow_unknown_ext_p, 0);
    rb_define_method(cMessagePack_Unpacker, "buffer", Unpacker_buffer, 0);
    rb_define_method(cMessagePack_Unpacker, "read", Unpacker_read, 0);
    rb_define_alias(cMessagePack_Unpacker, "unpack", "read");
    rb_define_method(cMessagePack_Unpacker, "skip", Unpacker_skip, 0);
    rb_define_method(cMessagePack_Unpacker, "skip_nil", Unpacker_skip_nil, 0);
    rb_define_method(cMessagePack_Unpacker, "read_array_header", Unpacker_read_array_header, 0);
    rb_define_method(cMessagePack_Unpacker, "read_map_header", Unpacker_read_map_header, 0);
    rb_define_method(cMessagePack_Unpacker, "feed", Unpacker_feed_reference, 1);
    rb_define_alias(cMessagePack_Unpacker, "feed_reference", "feed");
    rb_define_method(cMessagePack_Unpacker, "each", Unpacker_each, 0);
    rb_define_method(cMessagePack_Unpacker, "feed_each", Unpacker_feed_each, 1);
    rb_define_method(cMessagePack_Unpacker, "reset", Unpacker_reset, 0);

    rb_define_private_method(cMessagePack_Unpacker, "registered_types_internal", Unpacker_registered_types_internal, 0);
    rb_define_private_method(cMessagePack_Unpacker, "register_type_internal", Unpacker_register_type_internal, 3);

    rb_define_method(cMessagePack_Unpacker, "full_unpack", Unpacker_full_unpack, 0);
}
