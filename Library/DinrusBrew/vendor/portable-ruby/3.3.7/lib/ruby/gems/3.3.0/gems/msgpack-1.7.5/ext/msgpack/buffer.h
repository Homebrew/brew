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
#ifndef MSGPACK_RUBY_BUFFER_H__
#define MSGPACK_RUBY_BUFFER_H__

#include "compat.h"
#include "sysdep.h"

#ifndef MSGPACK_BUFFER_STRING_WRITE_REFERENCE_DEFAULT
#define MSGPACK_BUFFER_STRING_WRITE_REFERENCE_DEFAULT (512*1024)
#endif

/* at least 23 (RSTRING_EMBED_LEN_MAX) bytes */
#ifndef MSGPACK_BUFFER_STRING_WRITE_REFERENCE_MINIMUM
#define MSGPACK_BUFFER_STRING_WRITE_REFERENCE_MINIMUM 256
#endif

#ifndef MSGPACK_BUFFER_STRING_READ_REFERENCE_DEFAULT
#define MSGPACK_BUFFER_STRING_READ_REFERENCE_DEFAULT 256
#endif

/* at least 23 (RSTRING_EMBED_LEN_MAX) bytes */
#ifndef MSGPACK_BUFFER_STRING_READ_REFERENCE_MINIMUM
#define MSGPACK_BUFFER_STRING_READ_REFERENCE_MINIMUM 256
#endif

#ifndef MSGPACK_BUFFER_IO_BUFFER_SIZE_DEFAULT
#define MSGPACK_BUFFER_IO_BUFFER_SIZE_DEFAULT (32*1024)
#endif

#ifndef MSGPACK_BUFFER_IO_BUFFER_SIZE_MINIMUM
#define MSGPACK_BUFFER_IO_BUFFER_SIZE_MINIMUM (1024)
#endif

#define NO_MAPPED_STRING ((VALUE)0)

#ifndef RB_ENC_INTERNED_STR_NULL_CHECK
#define RB_ENC_INTERNED_STR_NULL_CHECK 0
#endif

extern int msgpack_rb_encindex_utf8;
extern int msgpack_rb_encindex_usascii;
extern int msgpack_rb_encindex_ascii8bit;

extern ID s_uminus;

struct msgpack_buffer_chunk_t;
typedef struct msgpack_buffer_chunk_t msgpack_buffer_chunk_t;

struct msgpack_buffer_t;
typedef struct msgpack_buffer_t msgpack_buffer_t;

/*
 * msgpack_buffer_chunk_t
 * +----------------+
 * | filled  | free |
 * +---------+------+
 * ^ first   ^ last
 */
struct msgpack_buffer_chunk_t {
    char* first;
    char* last;
    void* mem;
    msgpack_buffer_chunk_t* next;
    VALUE mapped_string;  /* RBString or NO_MAPPED_STRING */
    bool rmem;
};

struct msgpack_buffer_t {
    char* read_buffer;
    char* tail_buffer_end;

    msgpack_buffer_chunk_t tail;
    msgpack_buffer_chunk_t* head;
    msgpack_buffer_chunk_t* free_list;

    char* rmem_last;
    char* rmem_end;
    void** rmem_owner;

    VALUE io;
    VALUE io_buffer;
    ID io_write_all_method;
    ID io_partial_read_method;

    size_t write_reference_threshold;
    size_t read_reference_threshold;
    size_t io_buffer_size;
};

/*
 * initialization functions
 */
void msgpack_buffer_static_init(void);

void msgpack_buffer_static_destroy(void);

void msgpack_buffer_init(msgpack_buffer_t* b);

void msgpack_buffer_destroy(msgpack_buffer_t* b);

void msgpack_buffer_mark(void* b);

void msgpack_buffer_clear(msgpack_buffer_t* b);

size_t msgpack_buffer_memsize(const msgpack_buffer_t* b);

static inline void msgpack_buffer_set_write_reference_threshold(msgpack_buffer_t* b, size_t length)
{
    if(length < MSGPACK_BUFFER_STRING_WRITE_REFERENCE_MINIMUM) {
        length = MSGPACK_BUFFER_STRING_WRITE_REFERENCE_MINIMUM;
    }
    b->write_reference_threshold = length;
}

static inline void msgpack_buffer_set_read_reference_threshold(msgpack_buffer_t* b, size_t length)
{
    if(length < MSGPACK_BUFFER_STRING_READ_REFERENCE_MINIMUM) {
        length = MSGPACK_BUFFER_STRING_READ_REFERENCE_MINIMUM;
    }
    b->read_reference_threshold = length;
}

static inline void msgpack_buffer_set_io_buffer_size(msgpack_buffer_t* b, size_t length)
{
    if(length < MSGPACK_BUFFER_IO_BUFFER_SIZE_MINIMUM) {
        length = MSGPACK_BUFFER_IO_BUFFER_SIZE_MINIMUM;
    }
    b->io_buffer_size = length;
}

static inline void msgpack_buffer_reset_io(msgpack_buffer_t* b)
{
    b->io = Qnil;
}

static inline bool msgpack_buffer_has_io(msgpack_buffer_t* b)
{
    return b->io != Qnil;
}

static inline void msgpack_buffer_reset(msgpack_buffer_t* b)
{
    msgpack_buffer_clear(b);
    msgpack_buffer_reset_io(b);
}


/*
 * writer functions
 */

static inline size_t msgpack_buffer_writable_size(const msgpack_buffer_t* b)
{
    return b->tail_buffer_end - b->tail.last;
}

static inline void msgpack_buffer_write_1(msgpack_buffer_t* b, int byte)
{
    (*b->tail.last++) = (char) byte;
}

static inline void msgpack_buffer_write_2(msgpack_buffer_t* b, int byte1, unsigned char byte2)
{
    *(b->tail.last++) = (char) byte1;
    *(b->tail.last++) = (char) byte2;
}

static inline void msgpack_buffer_write_byte_and_data(msgpack_buffer_t* b, int byte, const void* data, size_t length)
{
    (*b->tail.last++) = (char) byte;

    memcpy(b->tail.last, data, length);
    b->tail.last += length;
}

void _msgpack_buffer_expand(msgpack_buffer_t* b, const char* data, size_t length, bool use_flush);

size_t msgpack_buffer_flush_to_io(msgpack_buffer_t* b, VALUE io, ID write_method, bool consume);

static inline size_t msgpack_buffer_flush(msgpack_buffer_t* b)
{
    if(b->io == Qnil) {
        return 0;
    }
    return msgpack_buffer_flush_to_io(b, b->io, b->io_write_all_method, true);
}

static inline void msgpack_buffer_ensure_writable(msgpack_buffer_t* b, size_t require)
{
    if(msgpack_buffer_writable_size(b) < require) {
        _msgpack_buffer_expand(b, NULL, require, true);
    }
}

static inline void _msgpack_buffer_append_impl(msgpack_buffer_t* b, const char* data, size_t length, bool flush_to_io)
{
    if(length == 0) {
        return;
    }

    if(length <= msgpack_buffer_writable_size(b)) {
        memcpy(b->tail.last, data, length);
        b->tail.last += length;
        return;
    }

    _msgpack_buffer_expand(b, data, length, flush_to_io);
}

static inline void msgpack_buffer_append(msgpack_buffer_t* b, const char* data, size_t length)
{
    _msgpack_buffer_append_impl(b, data, length, true);
}

static inline void msgpack_buffer_append_nonblock(msgpack_buffer_t* b, const char* data, size_t length)
{
    _msgpack_buffer_append_impl(b, data, length, false);
}

void _msgpack_buffer_append_long_string(msgpack_buffer_t* b, VALUE string);

static inline size_t msgpack_buffer_append_string(msgpack_buffer_t* b, VALUE string)
{
    size_t length = RSTRING_LEN(string);

    if(length > b->write_reference_threshold) {
        _msgpack_buffer_append_long_string(b, string);

    } else {
        msgpack_buffer_append(b, RSTRING_PTR(string), length);
    }

    return length;
}

static inline size_t msgpack_buffer_append_string_reference(msgpack_buffer_t* b, VALUE string)
{
    size_t length = RSTRING_LEN(string);
    if (length > 0) {
        _msgpack_buffer_append_long_string(b, string);
    }
    return length;
}


/*
 * IO functions
 */
size_t _msgpack_buffer_feed_from_io(msgpack_buffer_t* b);

size_t _msgpack_buffer_read_from_io_to_string(msgpack_buffer_t* b, VALUE string, size_t length);

size_t _msgpack_buffer_skip_from_io(msgpack_buffer_t* b, size_t length);


/*
 * reader functions
 */

static inline size_t msgpack_buffer_top_readable_size(const msgpack_buffer_t* b)
{
    return b->head->last - b->read_buffer;
}

size_t msgpack_buffer_all_readable_size(const msgpack_buffer_t* b);

bool _msgpack_buffer_shift_chunk(msgpack_buffer_t* b);

static inline void _msgpack_buffer_consumed(msgpack_buffer_t* b, size_t length)
{
    b->read_buffer += length;
    if(b->read_buffer >= b->head->last) {
        _msgpack_buffer_shift_chunk(b);
    }
}

static inline int msgpack_buffer_peek_top_1(msgpack_buffer_t* b)
{
    return (int) (unsigned char) b->read_buffer[0];
}

static inline int msgpack_buffer_read_top_1(msgpack_buffer_t* b)
{
    int r = (int) (unsigned char) b->read_buffer[0];

    _msgpack_buffer_consumed(b, 1);

    return r;
}

static inline int msgpack_buffer_read_1(msgpack_buffer_t* b)
{
    if(msgpack_buffer_top_readable_size(b) <= 0) {
        if(b->io == Qnil) {
            return -1;
        }
        _msgpack_buffer_feed_from_io(b);
    }

    int r = (int) (unsigned char) b->read_buffer[0];
    _msgpack_buffer_consumed(b, 1);

    return r;
}


/*
 * bulk read / skip functions
 */

size_t msgpack_buffer_read_nonblock(msgpack_buffer_t* b, char* buffer, size_t length);

static inline bool msgpack_buffer_ensure_readable(msgpack_buffer_t* b, size_t require)
{
    if(msgpack_buffer_top_readable_size(b) < require) {
        size_t sz = msgpack_buffer_all_readable_size(b);
        if(sz < require) {
            if(b->io == Qnil) {
                return false;
            }
            do {
                size_t rl = _msgpack_buffer_feed_from_io(b);
                sz += rl;
            } while(sz < require);
        }
    }
    return true;
}

bool _msgpack_buffer_read_all2(msgpack_buffer_t* b, char* buffer, size_t length);

static inline bool msgpack_buffer_read_all(msgpack_buffer_t* b, char* buffer, size_t length)
{
    size_t avail = msgpack_buffer_top_readable_size(b);
    if(avail < length) {
        return _msgpack_buffer_read_all2(b, buffer, length);
    }

    memcpy(buffer, b->read_buffer, length);
    _msgpack_buffer_consumed(b, length);
    return true;
}

static inline size_t msgpack_buffer_skip_nonblock(msgpack_buffer_t* b, size_t length)
{
    size_t avail = msgpack_buffer_top_readable_size(b);
    if(avail < length) {
        return msgpack_buffer_read_nonblock(b, NULL, length);
    }
    _msgpack_buffer_consumed(b, length);
    return length;
}

size_t msgpack_buffer_read_to_string_nonblock(msgpack_buffer_t* b, VALUE string, size_t length);

static inline size_t msgpack_buffer_read_to_string(msgpack_buffer_t* b, VALUE string, size_t length)
{
    if(length == 0) {
        return 0;
    }

    size_t avail = msgpack_buffer_top_readable_size(b);
    if(avail > 0) {
        return msgpack_buffer_read_to_string_nonblock(b, string, length);
    } else if(b->io != Qnil) {
        return _msgpack_buffer_read_from_io_to_string(b, string, length);
    } else {
        return 0;
    }
}

static inline size_t msgpack_buffer_skip(msgpack_buffer_t* b, size_t length)
{
    if(length == 0) {
        return 0;
    }

    size_t avail = msgpack_buffer_top_readable_size(b);
    if(avail > 0) {
        return msgpack_buffer_skip_nonblock(b, length);
    } else if(b->io != Qnil) {
        return _msgpack_buffer_skip_from_io(b, length);
    } else {
        return 0;
    }
}


VALUE msgpack_buffer_all_as_string(msgpack_buffer_t* b);

VALUE msgpack_buffer_all_as_string_array(msgpack_buffer_t* b);

static inline VALUE _msgpack_buffer_refer_head_mapped_string(msgpack_buffer_t* b, size_t length)
{
    size_t offset = b->read_buffer - b->head->first;
    return rb_str_substr(b->head->mapped_string, offset, length);
}

static inline VALUE msgpack_buffer_read_top_as_string(msgpack_buffer_t* b, size_t length, bool will_be_frozen, bool utf8)
{
    /* optimize */
    if(!will_be_frozen &&
            b->head->mapped_string != NO_MAPPED_STRING &&
            length >= b->read_reference_threshold) {
        VALUE result = _msgpack_buffer_refer_head_mapped_string(b, length);
        if (utf8) ENCODING_SET(result, msgpack_rb_encindex_utf8);
        _msgpack_buffer_consumed(b, length);
        return result;
    }

    VALUE result;

#ifdef HAVE_RB_ENC_INTERNED_STR
    if (will_be_frozen) {
        if (RB_ENC_INTERNED_STR_NULL_CHECK && length == 0) {
            result = rb_enc_interned_str("", length, utf8 ? rb_utf8_encoding() : rb_ascii8bit_encoding());
        } else {
            result = rb_enc_interned_str(b->read_buffer, length, utf8 ? rb_utf8_encoding() : rb_ascii8bit_encoding());
        }
    } else {
        if (utf8) {
            result = rb_utf8_str_new(b->read_buffer, length);
        } else {
            result = rb_str_new(b->read_buffer, length);
        }
    }
    _msgpack_buffer_consumed(b, length);
    return result;

#else

    if (utf8) {
        result = rb_utf8_str_new(b->read_buffer, length);
    } else {
        result = rb_str_new(b->read_buffer, length);
    }

    if (will_be_frozen) {
#if STR_UMINUS_DEDUPE_FROZEN
        // Starting from MRI 2.8 it is preferable to freeze the string
        // before deduplication so that it can be interned directly
        // otherwise it would be duplicated first which is wasteful.
        rb_str_freeze(result);
#endif //STR_UMINUS_DEDUPE_FROZEN
        // MRI 2.5 and older do not deduplicate strings that are already
        // frozen.
        result = rb_funcall(result, s_uminus, 0);
    }
    _msgpack_buffer_consumed(b, length);
    return result;

#endif // HAVE_RB_ENC_INTERNED_STR
}

static inline VALUE msgpack_buffer_read_top_as_symbol(msgpack_buffer_t* b, size_t length, bool utf8)
{
    return rb_str_intern(msgpack_buffer_read_top_as_string(b, length, true, utf8));
}

#endif
