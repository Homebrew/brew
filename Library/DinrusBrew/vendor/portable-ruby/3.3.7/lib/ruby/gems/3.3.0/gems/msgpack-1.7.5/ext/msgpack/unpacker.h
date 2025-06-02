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
#ifndef MSGPACK_RUBY_UNPACKER_H__
#define MSGPACK_RUBY_UNPACKER_H__

#include "buffer.h"
#include "unpacker_ext_registry.h"

#define MSGPACK_UNPACKER_STACK_CAPACITY 128

struct msgpack_unpacker_t;
typedef struct msgpack_unpacker_t msgpack_unpacker_t;
typedef struct msgpack_unpacker_stack_t msgpack_unpacker_stack_t;

enum stack_type_t {
    STACK_TYPE_ARRAY,
    STACK_TYPE_MAP_KEY,
    STACK_TYPE_MAP_VALUE,
    STACK_TYPE_RECURSIVE,
};

typedef struct {
    size_t count;
    enum stack_type_t type;
    VALUE object;
    VALUE key;
} msgpack_unpacker_stack_entry_t;

struct msgpack_unpacker_stack_t {
    size_t depth;
    size_t capacity;
    msgpack_unpacker_stack_entry_t *data;
};

struct msgpack_unpacker_t {
    msgpack_buffer_t buffer;
    msgpack_unpacker_stack_t stack;

    VALUE self;
    VALUE last_object;

    VALUE reading_raw;
    size_t reading_raw_remaining;

    VALUE buffer_ref;

    msgpack_unpacker_ext_registry_t *ext_registry;

    int reading_raw_type;
    unsigned int head_byte;

    /* options */
    int symbol_ext_type;
    bool symbolize_keys;
    bool freeze;
    bool allow_unknown_ext;
    bool optimized_symbol_ext_type;
};

#define UNPACKER_BUFFER_(uk) (&(uk)->buffer)

enum msgpack_unpacker_object_type {
    TYPE_NIL = 0,
    TYPE_BOOLEAN,
    TYPE_INTEGER,
    TYPE_FLOAT,
    TYPE_RAW,
    TYPE_ARRAY,
    TYPE_MAP,
};

void msgpack_unpacker_static_init(void);

void msgpack_unpacker_static_destroy(void);

void _msgpack_unpacker_init(msgpack_unpacker_t*);

void _msgpack_unpacker_destroy(msgpack_unpacker_t* uk);

void msgpack_unpacker_mark(msgpack_unpacker_t* uk);

void _msgpack_unpacker_reset(msgpack_unpacker_t* uk);

static inline void msgpack_unpacker_set_symbolized_keys(msgpack_unpacker_t* uk, bool enable)
{
    uk->symbolize_keys = enable;
}

static inline void msgpack_unpacker_set_freeze(msgpack_unpacker_t* uk, bool enable)
{
    uk->freeze = enable;
}

static inline void msgpack_unpacker_set_allow_unknown_ext(msgpack_unpacker_t* uk, bool enable)
{
    uk->allow_unknown_ext = enable;
}


/* error codes */
#define PRIMITIVE_CONTAINER_START 1
#define PRIMITIVE_OBJECT_COMPLETE 0
#define PRIMITIVE_EOF -1
#define PRIMITIVE_INVALID_BYTE -2
#define PRIMITIVE_STACK_TOO_DEEP -3
#define PRIMITIVE_UNEXPECTED_TYPE -4
#define PRIMITIVE_UNEXPECTED_EXT_TYPE -5
#define PRIMITIVE_RECURSIVE_RAISED -6

int msgpack_unpacker_read(msgpack_unpacker_t* uk, size_t target_stack_depth);

int msgpack_unpacker_skip(msgpack_unpacker_t* uk, size_t target_stack_depth);

static inline VALUE msgpack_unpacker_get_last_object(msgpack_unpacker_t* uk)
{
    return uk->last_object;
}


int msgpack_unpacker_peek_next_object_type(msgpack_unpacker_t* uk);

int msgpack_unpacker_skip_nil(msgpack_unpacker_t* uk);

int msgpack_unpacker_read_array_header(msgpack_unpacker_t* uk, uint32_t* result_size);

int msgpack_unpacker_read_map_header(msgpack_unpacker_t* uk, uint32_t* result_size);

#endif

