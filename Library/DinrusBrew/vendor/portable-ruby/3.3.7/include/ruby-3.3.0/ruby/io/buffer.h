#ifndef RUBY_IO_BUFFER_H
#define RUBY_IO_BUFFER_H
/**
 * @file
 * @author     Samuel Williams
 * @date       Fri  2 Jul 2021 16:29:01 NZST
 * @copyright  Copyright (C) 2021 Samuel Williams
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#pragma once

#include "ruby/ruby.h"
#include "ruby/internal/config.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

// WARNING: This entire interface is experimental and may change in the future!
#define RB_IO_BUFFER_EXPERIMENTAL 1

#define RUBY_IO_BUFFER_VERSION 2

// The `IO::Buffer` class.
RUBY_EXTERN VALUE rb_cIOBuffer;

// The operating system page size.
RUBY_EXTERN size_t RUBY_IO_BUFFER_PAGE_SIZE;

// The default buffer size, usually a (small) multiple of the page size.
// Can be overridden by the RUBY_IO_BUFFER_DEFAULT_SIZE environment variable.
RUBY_EXTERN size_t RUBY_IO_BUFFER_DEFAULT_SIZE;

// Represents the internal state of the buffer.
// More than one flag can be set at a time.
enum rb_io_buffer_flags {
    // The memory in the buffer is owned by someone else.
    // More specifically, it means that someone else owns the buffer and we shouldn't try to resize it.
    RB_IO_BUFFER_EXTERNAL = 1,
    // The memory in the buffer is allocated internally.
    RB_IO_BUFFER_INTERNAL = 2,
    // The memory in the buffer is mapped.
    // A non-private mapping is marked as external.
    RB_IO_BUFFER_MAPPED = 4,

    // A mapped buffer that is also shared.
    RB_IO_BUFFER_SHARED = 8,

    // The buffer is locked and cannot be resized.
    // More specifically, it means we can't change the base address or size.
    // A buffer is typically locked before a system call that uses the data.
    RB_IO_BUFFER_LOCKED = 32,

    // The buffer mapping is private and will not impact other processes or the underlying file.
    RB_IO_BUFFER_PRIVATE = 64,

    // The buffer is read-only and cannot be modified.
    RB_IO_BUFFER_READONLY = 128,

    // The buffer is backed by a file.
    RB_IO_BUFFER_FILE = 256,
};

// Represents the endian of the data types.
enum rb_io_buffer_endian {
    // The least significant units are put first.
    RB_IO_BUFFER_LITTLE_ENDIAN = 4,
    RB_IO_BUFFER_BIG_ENDIAN = 8,

#if defined(WORDS_BIGENDIAN)
    RB_IO_BUFFER_HOST_ENDIAN = RB_IO_BUFFER_BIG_ENDIAN,
#else
    RB_IO_BUFFER_HOST_ENDIAN = RB_IO_BUFFER_LITTLE_ENDIAN,
#endif

    RB_IO_BUFFER_NETWORK_ENDIAN = RB_IO_BUFFER_BIG_ENDIAN
};

VALUE rb_io_buffer_new(void *base, size_t size, enum rb_io_buffer_flags flags);
VALUE rb_io_buffer_map(VALUE io, size_t size, rb_off_t offset, enum rb_io_buffer_flags flags);

VALUE rb_io_buffer_lock(VALUE self);
VALUE rb_io_buffer_unlock(VALUE self);
int rb_io_buffer_try_unlock(VALUE self);

VALUE rb_io_buffer_free(VALUE self);
VALUE rb_io_buffer_free_locked(VALUE self);

// Access the internal buffer and flags. Validates the pointers.
// The points may not remain valid if the source buffer is manipulated.
// Consider using rb_io_buffer_lock if needed.
enum rb_io_buffer_flags rb_io_buffer_get_bytes(VALUE self, void **base, size_t *size);
void rb_io_buffer_get_bytes_for_reading(VALUE self, const void **base, size_t *size);
void rb_io_buffer_get_bytes_for_writing(VALUE self, void **base, size_t *size);

VALUE rb_io_buffer_transfer(VALUE self);
void rb_io_buffer_resize(VALUE self, size_t size);
void rb_io_buffer_clear(VALUE self, uint8_t value, size_t offset, size_t length);

// The length is the minimum required length.
VALUE rb_io_buffer_read(VALUE self, VALUE io, size_t length, size_t offset);
VALUE rb_io_buffer_pread(VALUE self, VALUE io, rb_off_t from, size_t length, size_t offset);
VALUE rb_io_buffer_write(VALUE self, VALUE io, size_t length, size_t offset);
VALUE rb_io_buffer_pwrite(VALUE self, VALUE io, rb_off_t from, size_t length, size_t offset);

RBIMPL_SYMBOL_EXPORT_END()

#endif  /* RUBY_IO_BUFFER_H */
