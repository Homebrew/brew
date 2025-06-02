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
#include "rmem.h"
#include "extension_value_class.h"
#include <assert.h>
#include <limits.h>

#if !defined(HAVE_RB_PROC_CALL_WITH_BLOCK)
#define rb_proc_call_with_block(recv, argc, argv, block) rb_funcallv(recv, rb_intern("call"), argc, argv)
#endif

struct protected_proc_call_args {
    VALUE proc;
    int argc;
    VALUE *argv;
};

static VALUE protected_proc_call_safe(VALUE _args) {
    struct protected_proc_call_args *args = (struct protected_proc_call_args *)_args;

    return rb_proc_call_with_block(args->proc, args->argc, args->argv, Qnil);
}

static VALUE protected_proc_call(VALUE proc, int argc, VALUE *argv, int *raised) {
    struct protected_proc_call_args args = {
      .proc = proc,
      .argc = argc,
      .argv = argv,
    };
    return rb_protect(protected_proc_call_safe, (VALUE)&args, raised);
}

static int RAW_TYPE_STRING = 256;
static int RAW_TYPE_BINARY = 257;
static int16_t INITIAL_BUFFER_CAPACITY_MAX = SHRT_MAX;

static msgpack_rmem_t s_stack_rmem;

#if !defined(HAVE_RB_HASH_NEW_CAPA)
static inline VALUE rb_hash_new_capa(long capa)
{
  return rb_hash_new();
}
#endif

static inline int16_t initial_buffer_size(long size)
{
    return (size > INITIAL_BUFFER_CAPACITY_MAX) ? INITIAL_BUFFER_CAPACITY_MAX : size;
}

void msgpack_unpacker_static_init(void)
{
    assert(sizeof(msgpack_unpacker_stack_entry_t) * MSGPACK_UNPACKER_STACK_CAPACITY <= MSGPACK_RMEM_PAGE_SIZE);

    msgpack_rmem_init(&s_stack_rmem);
}

void msgpack_unpacker_static_destroy(void)
{
    msgpack_rmem_destroy(&s_stack_rmem);
}

#define HEAD_BYTE_REQUIRED 0xc1

static inline void _msgpack_unpacker_stack_init(msgpack_unpacker_stack_t *stack) {
    stack->capacity = MSGPACK_UNPACKER_STACK_CAPACITY;
    stack->data = msgpack_rmem_alloc(&s_stack_rmem);
}

void _msgpack_unpacker_init(msgpack_unpacker_t* uk)
{
    msgpack_buffer_init(UNPACKER_BUFFER_(uk));

    uk->head_byte = HEAD_BYTE_REQUIRED;

    uk->last_object = Qnil;
    uk->reading_raw = Qnil;

    _msgpack_unpacker_stack_init(&uk->stack);
}

static inline void _msgpack_unpacker_free_stack(msgpack_unpacker_stack_t* stack) {
    if (!msgpack_rmem_free(&s_stack_rmem, stack->data)) {
        rb_bug("Failed to free an rmem pointer, memory leak?");
    }
    stack->data = NULL;
    stack->depth = 0;
}

void _msgpack_unpacker_destroy(msgpack_unpacker_t* uk)
{
    _msgpack_unpacker_free_stack(&uk->stack);
    msgpack_buffer_destroy(UNPACKER_BUFFER_(uk));
}

void msgpack_unpacker_mark_stack(msgpack_unpacker_stack_t* stack)
{
    if (stack->data) {
        msgpack_unpacker_stack_entry_t* s = stack->data;
        msgpack_unpacker_stack_entry_t* send = stack->data + stack->depth;
        for(; s < send; s++) {
            rb_gc_mark(s->object);
            rb_gc_mark(s->key);
        }
    }
}

void msgpack_unpacker_mark(msgpack_unpacker_t* uk)
{
    rb_gc_mark(uk->last_object);
    rb_gc_mark(uk->reading_raw);
    msgpack_unpacker_mark_stack(&uk->stack);
    /* See MessagePack_Buffer_wrap */
    /* msgpack_buffer_mark(UNPACKER_BUFFER_(uk)); */
    rb_gc_mark(uk->buffer_ref);
    rb_gc_mark(uk->self);
}

void _msgpack_unpacker_reset(msgpack_unpacker_t* uk)
{
    msgpack_buffer_clear(UNPACKER_BUFFER_(uk));

    uk->head_byte = HEAD_BYTE_REQUIRED;

    /*memset(uk->stack, 0, sizeof(msgpack_unpacker_t) * uk->stack.depth);*/
    uk->stack.depth = 0;
    uk->last_object = Qnil;
    uk->reading_raw = Qnil;
    uk->reading_raw_remaining = 0;
}


/* head byte functions */
static int read_head_byte(msgpack_unpacker_t* uk)
{
    int r = msgpack_buffer_read_1(UNPACKER_BUFFER_(uk));
    if(r == -1) {
        return PRIMITIVE_EOF;
    }
    return uk->head_byte = r;
}

static inline int get_head_byte(msgpack_unpacker_t* uk)
{
    int b = uk->head_byte;
    if(b == HEAD_BYTE_REQUIRED) {
        b = read_head_byte(uk);
    }
    return b;
}

static inline void reset_head_byte(msgpack_unpacker_t* uk)
{
    uk->head_byte = HEAD_BYTE_REQUIRED;
}

static inline int object_complete(msgpack_unpacker_t* uk, VALUE object)
{
    if(uk->freeze) {
        rb_obj_freeze(object);
    }

    uk->last_object = object;
    reset_head_byte(uk);
    return PRIMITIVE_OBJECT_COMPLETE;
}

static inline int object_complete_symbol(msgpack_unpacker_t* uk, VALUE object)
{
    uk->last_object = object;
    reset_head_byte(uk);
    return PRIMITIVE_OBJECT_COMPLETE;
}

static inline int object_complete_ext(msgpack_unpacker_t* uk, int ext_type, VALUE str)
{
    if (uk->optimized_symbol_ext_type && ext_type == uk->symbol_ext_type) {
        if (RB_UNLIKELY(NIL_P(str))) { // empty extension is returned as Qnil
            return object_complete_symbol(uk, ID2SYM(rb_intern3("", 0, rb_utf8_encoding())));
        }
        return object_complete_symbol(uk, rb_str_intern(str));
    }

    int ext_flags;
    VALUE proc = msgpack_unpacker_ext_registry_lookup(uk->ext_registry, ext_type, &ext_flags);

    if(proc != Qnil) {
        VALUE obj;
        VALUE arg = (str == Qnil ? rb_str_buf_new(0) : str);
        int raised;
        obj = protected_proc_call(proc, 1, &arg, &raised);
        if (raised) {
            uk->last_object = rb_errinfo();
            return PRIMITIVE_RECURSIVE_RAISED;
        }
        return object_complete(uk, obj);
    }

    if(uk->allow_unknown_ext) {
        VALUE obj = MessagePack_ExtensionValue_new(ext_type, str == Qnil ? rb_str_buf_new(0) : str);
        return object_complete(uk, obj);
    }

    return PRIMITIVE_UNEXPECTED_EXT_TYPE;
}

/* stack funcs */
static inline msgpack_unpacker_stack_entry_t* _msgpack_unpacker_stack_entry_top(msgpack_unpacker_t* uk)
{
    return &uk->stack.data[uk->stack.depth-1];
}

static inline int _msgpack_unpacker_stack_push(msgpack_unpacker_t* uk, enum stack_type_t type, size_t count, VALUE object)
{
    reset_head_byte(uk);

    if(uk->stack.capacity - uk->stack.depth <= 0) {
        return PRIMITIVE_STACK_TOO_DEEP;
    }

    msgpack_unpacker_stack_entry_t* next = &uk->stack.data[uk->stack.depth];
    next->count = count;
    next->type = type;
    next->object = object;
    next->key = Qnil;

    uk->stack.depth++;
    return PRIMITIVE_CONTAINER_START;
}

static inline size_t msgpack_unpacker_stack_pop(msgpack_unpacker_t* uk)
{
    return --uk->stack.depth;
}

static inline bool msgpack_unpacker_stack_is_empty(msgpack_unpacker_t* uk)
{
    return uk->stack.depth == 0;
}

#ifdef USE_CASE_RANGE

#define SWITCH_RANGE_BEGIN(BYTE)     { switch(BYTE) {
#define SWITCH_RANGE(BYTE, FROM, TO) } case FROM ... TO: {
#define SWITCH_RANGE_DEFAULT         } default: {
#define SWITCH_RANGE_END             } }

#else

#define SWITCH_RANGE_BEGIN(BYTE)     { if(0) {
#define SWITCH_RANGE(BYTE, FROM, TO) } else if(FROM <= (BYTE) && (BYTE) <= TO) {
#define SWITCH_RANGE_DEFAULT         } else {
#define SWITCH_RANGE_END             } }

#endif

union msgpack_buffer_cast_block_t {
    char buffer[8];
    uint8_t u8;
    uint16_t u16;
    uint32_t u32;
    uint64_t u64;
    int8_t i8;
    int16_t i16;
    int32_t i32;
    int64_t i64;
    float f;
    double d;
};

#define READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, n) \
    union msgpack_buffer_cast_block_t cb; \
    if (!msgpack_buffer_read_all(UNPACKER_BUFFER_(uk), (char *)&cb.buffer, n)) { \
        return PRIMITIVE_EOF; \
    }

static inline bool is_reading_map_key(msgpack_unpacker_t* uk)
{
    if(uk->stack.depth > 0) {
        msgpack_unpacker_stack_entry_t* top = _msgpack_unpacker_stack_entry_top(uk);
        if(top->type == STACK_TYPE_MAP_KEY) {
            return true;
        }
    }
    return false;
}

static int read_raw_body_cont(msgpack_unpacker_t* uk)
{
    size_t length = uk->reading_raw_remaining;

    if(uk->reading_raw == Qnil) {
        uk->reading_raw = rb_str_buf_new(length);
    }

    do {
        size_t n = msgpack_buffer_read_to_string(UNPACKER_BUFFER_(uk), uk->reading_raw, length);
        if(n == 0) {
            return PRIMITIVE_EOF;
        }
        /* update reading_raw_remaining everytime because
         * msgpack_buffer_read_to_string raises IOError */
        uk->reading_raw_remaining = length = length - n;
    } while(length > 0);

    int ret;
    if(uk->reading_raw_type == RAW_TYPE_STRING) {
        ENCODING_SET(uk->reading_raw, msgpack_rb_encindex_utf8);
        ret = object_complete(uk, uk->reading_raw);
    } else if (uk->reading_raw_type == RAW_TYPE_BINARY) {
        ret = object_complete(uk, uk->reading_raw);
    } else {
        ret = object_complete_ext(uk, uk->reading_raw_type, uk->reading_raw);
    }
    uk->reading_raw = Qnil;
    return ret;
}

static inline int read_raw_body_begin(msgpack_unpacker_t* uk, int raw_type)
{
    /* assuming uk->reading_raw == Qnil */

    int ext_flags;
    VALUE proc;

    if(!(raw_type == RAW_TYPE_STRING || raw_type == RAW_TYPE_BINARY)) {
        proc = msgpack_unpacker_ext_registry_lookup(uk->ext_registry, raw_type, &ext_flags);
        if(proc != Qnil && ext_flags & MSGPACK_EXT_RECURSIVE) {
            VALUE obj;
            uk->last_object = Qnil;
            reset_head_byte(uk);
            uk->reading_raw_remaining = 0;

            _msgpack_unpacker_stack_push(uk, STACK_TYPE_RECURSIVE, 1, Qnil);
            int raised;
            obj = protected_proc_call(proc, 1, &uk->self, &raised);
            msgpack_unpacker_stack_pop(uk);

            if (raised) {
                uk->last_object = rb_errinfo();
                return PRIMITIVE_RECURSIVE_RAISED;
            }

            return object_complete(uk, obj);
        }
    }

    /* try optimized read */
    size_t length = uk->reading_raw_remaining;
    if(length <= msgpack_buffer_top_readable_size(UNPACKER_BUFFER_(uk))) {
        int ret;
        if ((uk->optimized_symbol_ext_type && uk->symbol_ext_type == raw_type) || (uk->symbolize_keys && is_reading_map_key(uk))) {
            VALUE symbol = msgpack_buffer_read_top_as_symbol(UNPACKER_BUFFER_(uk), length, raw_type != RAW_TYPE_BINARY);
            ret = object_complete_symbol(uk, symbol);
        } else {
            bool will_freeze = uk->freeze;
            if(raw_type == RAW_TYPE_STRING || raw_type == RAW_TYPE_BINARY) {
               /* don't use zerocopy for hash keys but get a frozen string directly
                * because rb_hash_aset freezes keys and it causes copying */
                will_freeze = will_freeze || is_reading_map_key(uk);
                VALUE string = msgpack_buffer_read_top_as_string(UNPACKER_BUFFER_(uk), length, will_freeze, raw_type == RAW_TYPE_STRING);
                ret = object_complete(uk, string);
            } else {
                VALUE string = msgpack_buffer_read_top_as_string(UNPACKER_BUFFER_(uk), length, false, false);
                ret = object_complete_ext(uk, raw_type, string);
            }
        }
        uk->reading_raw_remaining = 0;
        return ret;
    }

    uk->reading_raw_type = raw_type;
    return read_raw_body_cont(uk);
}

static int read_primitive(msgpack_unpacker_t* uk)
{
    if(uk->reading_raw_remaining > 0) {
        return read_raw_body_cont(uk);
    }

    int b = get_head_byte(uk);
    if(b < 0) {
        return b;
    }

    SWITCH_RANGE_BEGIN(b)
    SWITCH_RANGE(b, 0x00, 0x7f)  // Positive Fixnum
        return object_complete(uk, INT2NUM(b));

    SWITCH_RANGE(b, 0xe0, 0xff)  // Negative Fixnum
        return object_complete(uk, INT2NUM((int8_t)b));

    SWITCH_RANGE(b, 0xa0, 0xbf)  // FixRaw / fixstr
        int count = b & 0x1f;
        /* read_raw_body_begin sets uk->reading_raw */
        uk->reading_raw_remaining = count;
        return read_raw_body_begin(uk, RAW_TYPE_STRING);

    SWITCH_RANGE(b, 0x90, 0x9f)  // FixArray
        int count = b & 0x0f;
        if(count == 0) {
            return object_complete(uk, rb_ary_new());
        }
        return _msgpack_unpacker_stack_push(uk, STACK_TYPE_ARRAY, count, rb_ary_new2(initial_buffer_size(count)));

    SWITCH_RANGE(b, 0x80, 0x8f)  // FixMap
        int count = b & 0x0f;
        if(count == 0) {
            return object_complete(uk, rb_hash_new());
        }
        return _msgpack_unpacker_stack_push(uk, STACK_TYPE_MAP_KEY, count*2, rb_hash_new_capa(initial_buffer_size(count)));

    SWITCH_RANGE(b, 0xc0, 0xdf)  // Variable
        switch(b) {
        case 0xc0:  // nil
            return object_complete(uk, Qnil);

        //case 0xc1:  // string

        case 0xc2:  // false
            return object_complete(uk, Qfalse);

        case 0xc3:  // true
            return object_complete(uk, Qtrue);

        case 0xc7: // ext 8
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
                uint8_t length = cb.u8;
                int ext_type = (signed char) cb.buffer[1];
                if(length == 0) {
                    return object_complete_ext(uk, ext_type, Qnil);
                }
                uk->reading_raw_remaining = length;
                return read_raw_body_begin(uk, ext_type);
            }

        case 0xc8: // ext 16
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 3);
                uint16_t length = _msgpack_be16(cb.u16);
                int ext_type = (signed char) cb.buffer[2];
                if(length == 0) {
                    return object_complete_ext(uk, ext_type, Qnil);
                }
                uk->reading_raw_remaining = length;
                return read_raw_body_begin(uk, ext_type);
            }

        case 0xc9: // ext 32
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 5);
                uint32_t length = _msgpack_be32(cb.u32);
                int ext_type = (signed char) cb.buffer[4];
                if(length == 0) {
                    return object_complete_ext(uk, ext_type, Qnil);
                }
                uk->reading_raw_remaining = length;
                return read_raw_body_begin(uk, ext_type);
            }

        case 0xca:  // float
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
                cb.u32 = _msgpack_be_float(cb.u32);
                return object_complete(uk, rb_float_new(cb.f));
            }

        case 0xcb:  // double
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 8);
                cb.u64 = _msgpack_be_double(cb.u64);
                return object_complete(uk, rb_float_new(cb.d));
            }

        case 0xcc:  // unsigned int  8
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                uint8_t u8 = cb.u8;
                return object_complete(uk, INT2NUM((int)u8));
            }

        case 0xcd:  // unsigned int 16
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
                uint16_t u16 = _msgpack_be16(cb.u16);
                return object_complete(uk, INT2NUM((int)u16));
            }

        case 0xce:  // unsigned int 32
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
                uint32_t u32 = _msgpack_be32(cb.u32);
                return object_complete(uk, ULONG2NUM(u32)); // long at least 32 bits
            }

        case 0xcf:  // unsigned int 64
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 8);
                uint64_t u64 = _msgpack_be64(cb.u64);
                return object_complete(uk, rb_ull2inum(u64));
            }

        case 0xd0:  // signed int  8
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                int8_t i8 = cb.i8;
                return object_complete(uk, INT2NUM((int)i8));
            }

        case 0xd1:  // signed int 16
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
                int16_t i16 = _msgpack_be16(cb.i16);
                return object_complete(uk, INT2NUM((int)i16));
            }

        case 0xd2:  // signed int 32
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
                int32_t i32 = _msgpack_be32(cb.i32);
                return object_complete(uk, LONG2NUM(i32)); // long at least 32 bits
            }

        case 0xd3:  // signed int 64
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 8);
                int64_t i64 = _msgpack_be64(cb.i64);
                return object_complete(uk, rb_ll2inum(i64));
            }

        case 0xd4:  // fixext 1
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                int ext_type = cb.i8;
                uk->reading_raw_remaining = 1;
                return read_raw_body_begin(uk, ext_type);
            }

        case 0xd5:  // fixext 2
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                int ext_type = cb.i8;
                uk->reading_raw_remaining = 2;
                return read_raw_body_begin(uk, ext_type);
            }

        case 0xd6:  // fixext 4
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                int ext_type = cb.i8;
                uk->reading_raw_remaining = 4;
                return read_raw_body_begin(uk, ext_type);
            }

        case 0xd7:  // fixext 8
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                int ext_type = cb.i8;
                uk->reading_raw_remaining = 8;
                return read_raw_body_begin(uk, ext_type);
            }

        case 0xd8:  // fixext 16
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                int ext_type = cb.i8;
                uk->reading_raw_remaining = 16;
                return read_raw_body_begin(uk, ext_type);
            }


        case 0xd9:  // raw 8 / str 8
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                uint8_t count = cb.u8;
                /* read_raw_body_begin sets uk->reading_raw */
                uk->reading_raw_remaining = count;
                return read_raw_body_begin(uk, RAW_TYPE_STRING);
            }

        case 0xda:  // raw 16 / str 16
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
                uint16_t count = _msgpack_be16(cb.u16);
                /* read_raw_body_begin sets uk->reading_raw */
                uk->reading_raw_remaining = count;
                return read_raw_body_begin(uk, RAW_TYPE_STRING);
            }

        case 0xdb:  // raw 32 / str 32
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
                uint32_t count = _msgpack_be32(cb.u32);
                /* read_raw_body_begin sets uk->reading_raw */
                uk->reading_raw_remaining = count;
                return read_raw_body_begin(uk, RAW_TYPE_STRING);
            }

        case 0xc4:  // bin 8
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 1);
                uint8_t count = cb.u8;
                /* read_raw_body_begin sets uk->reading_raw */
                uk->reading_raw_remaining = count;
                return read_raw_body_begin(uk, RAW_TYPE_BINARY);
            }

        case 0xc5:  // bin 16
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
                uint16_t count = _msgpack_be16(cb.u16);
                /* read_raw_body_begin sets uk->reading_raw */
                uk->reading_raw_remaining = count;
                return read_raw_body_begin(uk, RAW_TYPE_BINARY);
            }

        case 0xc6:  // bin 32
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
                uint32_t count = _msgpack_be32(cb.u32);
                /* read_raw_body_begin sets uk->reading_raw */
                uk->reading_raw_remaining = count;
                return read_raw_body_begin(uk, RAW_TYPE_BINARY);
            }

        case 0xdc:  // array 16
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
                uint16_t count = _msgpack_be16(cb.u16);
                if(count == 0) {
                    return object_complete(uk, rb_ary_new());
                }
                return _msgpack_unpacker_stack_push(uk, STACK_TYPE_ARRAY, count, rb_ary_new2(initial_buffer_size(count)));
            }

        case 0xdd:  // array 32
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
                uint32_t count = _msgpack_be32(cb.u32);
                if(count == 0) {
                    return object_complete(uk, rb_ary_new());
                }
                return _msgpack_unpacker_stack_push(uk, STACK_TYPE_ARRAY, count, rb_ary_new2(initial_buffer_size(count)));
            }

        case 0xde:  // map 16
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
                uint16_t count = _msgpack_be16(cb.u16);
                if(count == 0) {
                    return object_complete(uk, rb_hash_new());
                }
                return _msgpack_unpacker_stack_push(uk, STACK_TYPE_MAP_KEY, count*2, rb_hash_new_capa(initial_buffer_size(count)));
            }

        case 0xdf:  // map 32
            {
                READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
                uint32_t count = _msgpack_be32(cb.u32);
                if(count == 0) {
                    return object_complete(uk, rb_hash_new());
                }
                return _msgpack_unpacker_stack_push(uk, STACK_TYPE_MAP_KEY, count*2, rb_hash_new_capa(initial_buffer_size(count)));
            }

        default:
            return PRIMITIVE_INVALID_BYTE;
        }

    SWITCH_RANGE_DEFAULT
        return PRIMITIVE_INVALID_BYTE;

    SWITCH_RANGE_END
}

int msgpack_unpacker_read_array_header(msgpack_unpacker_t* uk, uint32_t* result_size)
{
    int b = get_head_byte(uk);
    if(b < 0) {
        return b;
    }

    if(0x90 <= b && b <= 0x9f) {
        *result_size = b & 0x0f;

    } else if(b == 0xdc) {
        /* array 16 */
        READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
        *result_size = _msgpack_be16(cb.u16);

    } else if(b == 0xdd) {
        /* array 32 */
        READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
        *result_size = _msgpack_be32(cb.u32);

    } else {
        return PRIMITIVE_UNEXPECTED_TYPE;
    }

    reset_head_byte(uk);
    return 0;
}

int msgpack_unpacker_read_map_header(msgpack_unpacker_t* uk, uint32_t* result_size)
{
    int b = get_head_byte(uk);
    if(b < 0) {
        return b;
    }

    if(0x80 <= b && b <= 0x8f) {
        *result_size = b & 0x0f;

    } else if(b == 0xde) {
        /* map 16 */
        READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 2);
        *result_size = _msgpack_be16(cb.u16);

    } else if(b == 0xdf) {
        /* map 32 */
        READ_CAST_BLOCK_OR_RETURN_EOF(cb, uk, 4);
        *result_size = _msgpack_be32(cb.u32);

    } else {
        return PRIMITIVE_UNEXPECTED_TYPE;
    }

    reset_head_byte(uk);
    return 0;
}

int msgpack_unpacker_read(msgpack_unpacker_t* uk, size_t target_stack_depth)
{
    while(true) {
        int r = read_primitive(uk);
        if(r < 0) {
            return r;
        }
        if(r == PRIMITIVE_CONTAINER_START) {
            continue;
        }
        /* PRIMITIVE_OBJECT_COMPLETE */

        if(msgpack_unpacker_stack_is_empty(uk)) {
            return PRIMITIVE_OBJECT_COMPLETE;
        }

        container_completed:
        {
            msgpack_unpacker_stack_entry_t* top = _msgpack_unpacker_stack_entry_top(uk);
            switch(top->type) {
            case STACK_TYPE_ARRAY:
                rb_ary_push(top->object, uk->last_object);
                break;
            case STACK_TYPE_MAP_KEY:
                top->key = uk->last_object;
                top->type = STACK_TYPE_MAP_VALUE;
                break;
            case STACK_TYPE_MAP_VALUE:
                if(uk->symbolize_keys && rb_type(top->key) == T_STRING) {
                    /* here uses rb_str_intern instead of rb_intern so that Ruby VM can GC unused symbols */
                    rb_hash_aset(top->object, rb_str_intern(top->key), uk->last_object);
                } else {
                    rb_hash_aset(top->object, top->key, uk->last_object);
                }
                top->type = STACK_TYPE_MAP_KEY;
                break;
            case STACK_TYPE_RECURSIVE:
                return PRIMITIVE_OBJECT_COMPLETE;
            }
            size_t count = --top->count;

            if(count == 0) {
                object_complete(uk, top->object);
                if(msgpack_unpacker_stack_pop(uk) <= target_stack_depth) {
                    return PRIMITIVE_OBJECT_COMPLETE;
                }
                goto container_completed;
            }
        }
    }
}

int msgpack_unpacker_skip(msgpack_unpacker_t* uk, size_t target_stack_depth)
{
    while(true) {
        int r = read_primitive(uk);
        if(r < 0) {
            return r;
        }
        if(r == PRIMITIVE_CONTAINER_START) {
            continue;
        }
        /* PRIMITIVE_OBJECT_COMPLETE */

        if(msgpack_unpacker_stack_is_empty(uk)) {
            return PRIMITIVE_OBJECT_COMPLETE;
        }

        container_completed:
        {
            msgpack_unpacker_stack_entry_t* top = _msgpack_unpacker_stack_entry_top(uk);

            /* this section optimized out */
            // TODO object_complete still creates objects which should be optimized out

            size_t count = --top->count;

            if(count == 0) {
                object_complete(uk, Qnil);
                if(msgpack_unpacker_stack_pop(uk) <= target_stack_depth) {
                    return PRIMITIVE_OBJECT_COMPLETE;
                }
                goto container_completed;
            }
        }
    }
}

int msgpack_unpacker_peek_next_object_type(msgpack_unpacker_t* uk)
{
    int b = get_head_byte(uk);
    if(b < 0) {
        return b;
    }

    SWITCH_RANGE_BEGIN(b)
    SWITCH_RANGE(b, 0x00, 0x7f)  // Positive Fixnum
        return TYPE_INTEGER;

    SWITCH_RANGE(b, 0xe0, 0xff)  // Negative Fixnum
        return TYPE_INTEGER;

    SWITCH_RANGE(b, 0xa0, 0xbf)  // FixRaw
        return TYPE_RAW;

    SWITCH_RANGE(b, 0x90, 0x9f)  // FixArray
        return TYPE_ARRAY;

    SWITCH_RANGE(b, 0x80, 0x8f)  // FixMap
        return TYPE_MAP;

    SWITCH_RANGE(b, 0xc0, 0xdf)  // Variable
        switch(b) {
        case 0xc0:  // nil
            return TYPE_NIL;

        case 0xc2:  // false
        case 0xc3:  // true
            return TYPE_BOOLEAN;

        case 0xca:  // float
        case 0xcb:  // double
            return TYPE_FLOAT;

        case 0xcc:  // unsigned int  8
        case 0xcd:  // unsigned int 16
        case 0xce:  // unsigned int 32
        case 0xcf:  // unsigned int 64
            return TYPE_INTEGER;

        case 0xd0:  // signed int  8
        case 0xd1:  // signed int 16
        case 0xd2:  // signed int 32
        case 0xd3:  // signed int 64
            return TYPE_INTEGER;

        case 0xd9:  // raw 8 / str 8
        case 0xda:  // raw 16 / str 16
        case 0xdb:  // raw 32 / str 32
            return TYPE_RAW;

        case 0xc4:  // bin 8
        case 0xc5:  // bin 16
        case 0xc6:  // bin 32
            return TYPE_RAW;

        case 0xdc:  // array 16
        case 0xdd:  // array 32
            return TYPE_ARRAY;

        case 0xde:  // map 16
        case 0xdf:  // map 32
            return TYPE_MAP;

        default:
            return PRIMITIVE_INVALID_BYTE;
        }

    SWITCH_RANGE_DEFAULT
        return PRIMITIVE_INVALID_BYTE;

    SWITCH_RANGE_END
}

int msgpack_unpacker_skip_nil(msgpack_unpacker_t* uk)
{
    int b = get_head_byte(uk);
    if(b < 0) {
        return b;
    }
    if(b == 0xc0) {
        return 1;
    }
    return 0;
}

