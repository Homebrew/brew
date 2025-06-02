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
#ifndef MSGPACK_RUBY_UNPACKER_CLASS_H__
#define MSGPACK_RUBY_UNPACKER_CLASS_H__

#include "unpacker.h"

extern const rb_data_type_t unpacker_data_type;

static inline msgpack_unpacker_t *MessagePack_Unpacker_get(VALUE object) {
    msgpack_unpacker_t *unpacker;
    TypedData_Get_Struct(object, msgpack_unpacker_t, &unpacker_data_type, unpacker);
    if (!unpacker) {
        rb_raise(rb_eArgError, "Uninitialized Unpacker object");
    }
    return unpacker;
}

extern VALUE cMessagePack_Unpacker;

void MessagePack_Unpacker_module_init(VALUE mMessagePack);

VALUE MessagePack_Unpacker_alloc(VALUE klass);

VALUE MessagePack_Unpacker_initialize(int argc, VALUE* argv, VALUE self);

#endif

