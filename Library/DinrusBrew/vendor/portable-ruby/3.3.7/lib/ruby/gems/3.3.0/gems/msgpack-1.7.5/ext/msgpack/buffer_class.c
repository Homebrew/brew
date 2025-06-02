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
#include "buffer.h"
#include "buffer_class.h"

VALUE cMessagePack_Buffer = Qnil;
VALUE cMessagePack_HeldBuffer = Qnil;

static ID s_read;
static ID s_readpartial;
static ID s_write;
static ID s_append;
static ID s_close;
static ID s_at_owner;

static VALUE sym_read_reference_threshold;
static VALUE sym_write_reference_threshold;
static VALUE sym_io_buffer_size;

typedef struct msgpack_held_buffer_t msgpack_held_buffer_t;
struct msgpack_held_buffer_t {
    size_t size;
    VALUE mapped_strings[];
};

static void HeldBuffer_mark(void *data)
{
    msgpack_held_buffer_t* held_buffer = (msgpack_held_buffer_t*)data;
    for (size_t index = 0; index < held_buffer->size; index++) {
        rb_gc_mark(held_buffer->mapped_strings[index]);
    }
}

static size_t HeldBuffer_memsize(const void *data)
{
    const msgpack_held_buffer_t* held_buffer = (msgpack_held_buffer_t*)data;
    return sizeof(size_t) + sizeof(VALUE) * held_buffer->size;
}

static const rb_data_type_t held_buffer_data_type = {
    .wrap_struct_name = "msgpack:held_buffer",
    .function = {
        .dmark = HeldBuffer_mark,
        .dfree = RUBY_TYPED_DEFAULT_FREE,
        .dsize = HeldBuffer_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

VALUE MessagePack_Buffer_hold(msgpack_buffer_t* buffer)
{
    size_t mapped_strings_count = 0;
    msgpack_buffer_chunk_t* c = buffer->head;
    while (c != &buffer->tail) {
        if (c->mapped_string != NO_MAPPED_STRING) {
            mapped_strings_count++;
        }
        c = c->next;
    }
    if (c->mapped_string != NO_MAPPED_STRING) {
        mapped_strings_count++;
    }

    if (mapped_strings_count == 0) {
        return Qnil;
    }

    msgpack_held_buffer_t* held_buffer = xmalloc(sizeof(msgpack_held_buffer_t) + mapped_strings_count * sizeof(VALUE));

    c = buffer->head;
    mapped_strings_count = 0;
    while (c != &buffer->tail) {
        if (c->mapped_string != NO_MAPPED_STRING) {
            held_buffer->mapped_strings[mapped_strings_count] = c->mapped_string;
            mapped_strings_count++;
        }
        c = c->next;
    }
    if (c->mapped_string != NO_MAPPED_STRING) {
        held_buffer->mapped_strings[mapped_strings_count] = c->mapped_string;
        mapped_strings_count++;
    }
    held_buffer->size = mapped_strings_count;
    return TypedData_Wrap_Struct(cMessagePack_HeldBuffer, &held_buffer_data_type, held_buffer);
}


#define CHECK_STRING_TYPE(value) \
    value = rb_check_string_type(value); \
    if( NIL_P(value) ) { \
        rb_raise(rb_eTypeError, "instance of String needed"); \
    }

static void Buffer_free(void* data)
{
    if(data == NULL) {
        return;
    }
    msgpack_buffer_t* b = (msgpack_buffer_t*) data;
    msgpack_buffer_destroy(b);
    xfree(b);
}

static size_t Buffer_memsize(const void *data)
{
    return sizeof(msgpack_buffer_t) + msgpack_buffer_memsize(data);
}

static const rb_data_type_t buffer_data_type = {
    .wrap_struct_name = "msgpack:buffer",
    .function = {
        .dmark = msgpack_buffer_mark,
        .dfree = Buffer_free,
        .dsize = Buffer_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static const rb_data_type_t buffer_view_data_type = {
    .wrap_struct_name = "msgpack:buffer_view",
    .function = {
        .dmark = NULL,
        .dfree = NULL,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static inline msgpack_buffer_t *MessagePack_Buffer_get(VALUE object)
{
    msgpack_buffer_t *buffer;
    bool view = RTEST(rb_ivar_get(object, s_at_owner));
    TypedData_Get_Struct(object, msgpack_buffer_t, view ? &buffer_view_data_type : &buffer_data_type, buffer);
    if (!buffer) {
        rb_raise(rb_eArgError, "Uninitialized Buffer object");
    }
    return buffer;
}

static VALUE Buffer_alloc(VALUE klass)
{
    msgpack_buffer_t* b;
    VALUE buffer = TypedData_Make_Struct(klass, msgpack_buffer_t, &buffer_data_type, b);
    msgpack_buffer_init(b);
    rb_ivar_set(buffer, s_at_owner, Qnil);
    return buffer;
}

static ID get_partial_read_method(VALUE io)
{
    if(io != Qnil && rb_respond_to(io, s_readpartial)) {
        return s_readpartial;
    }
    return s_read;
}

static ID get_write_all_method(VALUE io)
{
    if(io != Qnil) {
        if(rb_respond_to(io, s_write)) {
            return s_write;
        } else if(rb_respond_to(io, s_append)) {
            return s_append;
        }
    }
    return s_write;
}

void MessagePack_Buffer_set_options(msgpack_buffer_t* b, VALUE io, VALUE options)
{
    b->io = io;
    b->io_partial_read_method = get_partial_read_method(io);
    b->io_write_all_method = get_write_all_method(io);

    if(options != Qnil) {
        VALUE v;

        v = rb_hash_aref(options, sym_read_reference_threshold);
        if(v != Qnil) {
            msgpack_buffer_set_read_reference_threshold(b, NUM2SIZET(v));
        }

        v = rb_hash_aref(options, sym_write_reference_threshold);
        if(v != Qnil) {
            msgpack_buffer_set_write_reference_threshold(b, NUM2SIZET(v));
        }

        v = rb_hash_aref(options, sym_io_buffer_size);
        if(v != Qnil) {
            msgpack_buffer_set_io_buffer_size(b, NUM2SIZET(v));
        }
    }
}

VALUE MessagePack_Buffer_wrap(msgpack_buffer_t* b, VALUE owner)
{
    VALUE buffer = TypedData_Wrap_Struct(cMessagePack_Buffer, &buffer_view_data_type, b);
    rb_ivar_set(buffer, s_at_owner, owner);
    return buffer;
}

static VALUE Buffer_initialize(int argc, VALUE* argv, VALUE self)
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
        if(rb_type(options) != T_HASH) {
            rb_raise(rb_eArgError, "expected Hash but found %s.", rb_obj_classname(io));
        }

    } else {
        rb_raise(rb_eArgError, "wrong number of arguments (%d for 0..1)", argc);
    }

    msgpack_buffer_t *b = MessagePack_Buffer_get(self);

    MessagePack_Buffer_set_options(b, io, options);

    return self;
}

static VALUE Buffer_clear(VALUE self)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    msgpack_buffer_clear(b);
    return Qnil;
}

static VALUE Buffer_size(VALUE self)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    size_t size = msgpack_buffer_all_readable_size(b);
    return SIZET2NUM(size);
}

static VALUE Buffer_empty_p(VALUE self)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    if(msgpack_buffer_top_readable_size(b) == 0) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

static VALUE Buffer_write(VALUE self, VALUE string_or_buffer)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);

    VALUE string = string_or_buffer;  // TODO optimize if string_or_buffer is a Buffer
    StringValue(string);

    size_t length = msgpack_buffer_append_string(b, string);

    return SIZET2NUM(length);
}

static VALUE Buffer_append(VALUE self, VALUE string_or_buffer)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);

    VALUE string = string_or_buffer;  // TODO optimize if string_or_buffer is a Buffer
    StringValue(string);

    msgpack_buffer_append_string(b, string);

    return self;
}


#define MAKE_EMPTY_STRING(orig) \
    if(orig == Qnil) { \
        orig = rb_str_buf_new(0); \
    } else { \
        rb_str_resize(orig, 0); \
    }

static VALUE read_until_eof_rescue(VALUE args)
{
    msgpack_buffer_t* b = (void*) ((VALUE*) args)[0];
    VALUE out = ((VALUE*) args)[1];
    unsigned long max = ((VALUE*) args)[2];
    size_t* sz = (void*) ((VALUE*) args)[3];

    while(true) {
        size_t rl;
        if(max == 0) {
            if(out == Qnil) {
                rl = msgpack_buffer_skip(b, b->io_buffer_size);
            } else {
                rl = msgpack_buffer_read_to_string(b, out, b->io_buffer_size);
            }
            if(rl == 0) {
                break;
            }
            *sz += rl;

        } else {
            if(out == Qnil) {
                rl = msgpack_buffer_skip(b, max);
            } else {
                rl = msgpack_buffer_read_to_string(b, out, max);
            }
            if(rl == 0) {
                break;
            }
            *sz += rl;
            if(max <= rl) {
                break;
            } else {
                max -= rl;
            }
        }
    }

    return Qnil;
}

static VALUE read_until_eof_error(VALUE args, VALUE error)
{
    /* ignore EOFError */
    UNUSED(args);
    UNUSED(error);
    return Qnil;
}

static inline size_t read_until_eof(msgpack_buffer_t* b, VALUE out, unsigned long max)
{
    if(msgpack_buffer_has_io(b)) {
        size_t sz = 0;
        VALUE args[4] = { (VALUE)(void*) b, out, (VALUE) max, (VALUE)(void*) &sz };
        rb_rescue2(read_until_eof_rescue, (VALUE)(void*) args,
                read_until_eof_error, (VALUE)(void*) args,
                rb_eEOFError, NULL);
        return sz;

    } else {
        if(max == 0) {
            max = ULONG_MAX;
        }
        if(out == Qnil) {
            return msgpack_buffer_skip_nonblock(b, max);
        } else {
            return msgpack_buffer_read_to_string_nonblock(b, out, max);
        }
    }
}

static inline VALUE read_all(msgpack_buffer_t* b, VALUE out)
{
    if(out == Qnil && !msgpack_buffer_has_io(b)) {
        /* same as to_s && clear; optimize */
        VALUE str = msgpack_buffer_all_as_string(b);
        msgpack_buffer_clear(b);
        return str;
    }

    MAKE_EMPTY_STRING(out);
    read_until_eof(b, out, 0);
    return out;
}

static VALUE Buffer_skip(VALUE self, VALUE sn)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);

    unsigned long n = FIX2ULONG(sn);

    /* do nothing */
    if(n == 0) {
        return INT2NUM(0);
    }

    size_t sz = read_until_eof(b, Qnil, n);
    return SIZET2NUM(sz);
}

static VALUE Buffer_skip_all(VALUE self, VALUE sn)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);

    unsigned long n = FIX2ULONG(sn);

    /* do nothing */
    if(n == 0) {
        return self;
    }

    if(!msgpack_buffer_ensure_readable(b, n)) {
        rb_raise(rb_eEOFError, "end of buffer reached");
    }

    msgpack_buffer_skip_nonblock(b, n);

    return self;
}

static VALUE Buffer_read_all(int argc, VALUE* argv, VALUE self)
{
    VALUE out = Qnil;
    unsigned long n = 0;
    bool all = false;

    switch(argc) {
    case 2:
        out = argv[1];
        /* pass through */
    case 1:
        n = FIX2ULONG(argv[0]);
        break;
    case 0:
        all = true;
        break;
    default:
        rb_raise(rb_eArgError, "wrong number of arguments (%d for 0..2)", argc);
    }

    msgpack_buffer_t *b = MessagePack_Buffer_get(self);

    if(out != Qnil) {
        CHECK_STRING_TYPE(out);
    }

    if(all) {
        return read_all(b, out);
    }

    if(n == 0) {
        /* do nothing */
        MAKE_EMPTY_STRING(out);
        return out;
    }

    if(!msgpack_buffer_ensure_readable(b, n)) {
        rb_raise(rb_eEOFError, "end of buffer reached");
    }

    MAKE_EMPTY_STRING(out);
    msgpack_buffer_read_to_string_nonblock(b, out, n);

    return out;
}

static VALUE Buffer_read(int argc, VALUE* argv, VALUE self)
{
    VALUE out = Qnil;
    unsigned long n = -1;
    bool all = false;

    switch(argc) {
    case 2:
        out = argv[1];
        /* pass through */
    case 1:
        n = FIX2ULONG(argv[0]);
        break;
    case 0:
        all = true;
        break;
    default:
        rb_raise(rb_eArgError, "wrong number of arguments (%d for 0..2)", argc);
    }

    msgpack_buffer_t *b = MessagePack_Buffer_get(self);

    if(out != Qnil) {
        CHECK_STRING_TYPE(out);
    }

    if(all) {
        return read_all(b, out);
    }

    if(n == 0) {
        /* do nothing */
        MAKE_EMPTY_STRING(out);
        return out;
    }

    if(!msgpack_buffer_has_io(b) && out == Qnil &&
            msgpack_buffer_all_readable_size(b) <= n) {
        /* same as to_s && clear; optimize */
        VALUE str = msgpack_buffer_all_as_string(b);
        msgpack_buffer_clear(b);

        if(RSTRING_LEN(str) == 0) {
            return Qnil;
        } else {
            return str;
        }
    }

    MAKE_EMPTY_STRING(out);
    read_until_eof(b, out, n);

    if(RSTRING_LEN(out) == 0) {
        return Qnil;
    } else {
        return out;
    }
}

static VALUE Buffer_to_str(VALUE self)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    return msgpack_buffer_all_as_string(b);
}

static VALUE Buffer_to_a(VALUE self)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    return msgpack_buffer_all_as_string_array(b);
}

static VALUE Buffer_flush(VALUE self)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    msgpack_buffer_flush(b);
    return self;
}

static VALUE Buffer_io(VALUE self)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    return b->io;
}

static VALUE Buffer_close(VALUE self)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    if(b->io != Qnil) {
        return rb_funcall(b->io, s_close, 0);
    }
    return Qnil;
}

static VALUE Buffer_write_to(VALUE self, VALUE io)
{
    msgpack_buffer_t *b = MessagePack_Buffer_get(self);
    size_t sz = msgpack_buffer_flush_to_io(b, io, s_write, true);
    return SIZET2NUM(sz);
}

void MessagePack_Buffer_module_init(VALUE mMessagePack)
{
    s_read = rb_intern("read");
    s_readpartial = rb_intern("readpartial");
    s_write = rb_intern("write");
    s_append = rb_intern("<<");
    s_close = rb_intern("close");
    s_at_owner = rb_intern("@owner");

    sym_read_reference_threshold = ID2SYM(rb_intern("read_reference_threshold"));
    sym_write_reference_threshold = ID2SYM(rb_intern("write_reference_threshold"));
    sym_io_buffer_size = ID2SYM(rb_intern("io_buffer_size"));

    msgpack_buffer_static_init();

    cMessagePack_HeldBuffer = rb_define_class_under(mMessagePack, "HeldBuffer", rb_cBasicObject);
    rb_undef_alloc_func(cMessagePack_HeldBuffer);

    cMessagePack_Buffer = rb_define_class_under(mMessagePack, "Buffer", rb_cObject);

    rb_define_alloc_func(cMessagePack_Buffer, Buffer_alloc);

    rb_define_method(cMessagePack_Buffer, "initialize", Buffer_initialize, -1);
    rb_define_method(cMessagePack_Buffer, "clear", Buffer_clear, 0);
    rb_define_method(cMessagePack_Buffer, "size", Buffer_size, 0);
    rb_define_method(cMessagePack_Buffer, "empty?", Buffer_empty_p, 0);
    rb_define_method(cMessagePack_Buffer, "write", Buffer_write, 1);
    rb_define_method(cMessagePack_Buffer, "<<", Buffer_append, 1);
    rb_define_method(cMessagePack_Buffer, "skip", Buffer_skip, 1);
    rb_define_method(cMessagePack_Buffer, "skip_all", Buffer_skip_all, 1);
    rb_define_method(cMessagePack_Buffer, "read", Buffer_read, -1);
    rb_define_method(cMessagePack_Buffer, "read_all", Buffer_read_all, -1);
    rb_define_method(cMessagePack_Buffer, "io", Buffer_io, 0);
    rb_define_method(cMessagePack_Buffer, "flush", Buffer_flush, 0);
    rb_define_method(cMessagePack_Buffer, "close", Buffer_close, 0);
    rb_define_method(cMessagePack_Buffer, "write_to", Buffer_write_to, 1);
    rb_define_method(cMessagePack_Buffer, "to_str", Buffer_to_str, 0);
    rb_define_alias(cMessagePack_Buffer, "to_s", "to_str");
    rb_define_method(cMessagePack_Buffer, "to_a", Buffer_to_a, 0);
}

