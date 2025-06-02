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

#include "factory_class.h"
#include "packer_ext_registry.h"
#include "unpacker_ext_registry.h"
#include "buffer_class.h"
#include "packer_class.h"
#include "unpacker_class.h"

VALUE cMessagePack_Factory;

struct msgpack_factory_t;
typedef struct msgpack_factory_t msgpack_factory_t;

struct msgpack_factory_t {
    msgpack_packer_ext_registry_t pkrg;
    msgpack_unpacker_ext_registry_t *ukrg;
    bool has_bigint_ext_type;
    bool has_symbol_ext_type;
    bool optimized_symbol_ext_type;
    int symbol_ext_type;
};

static void Factory_free(void *ptr)
{
    msgpack_factory_t *fc = ptr;

    if(fc == NULL) {
        return;
    }
    msgpack_packer_ext_registry_destroy(&fc->pkrg);
    msgpack_unpacker_ext_registry_release(fc->ukrg);
    xfree(fc);
}

void Factory_mark(void *ptr)
{
    msgpack_factory_t *fc = ptr;
    msgpack_packer_ext_registry_mark(&fc->pkrg);
    msgpack_unpacker_ext_registry_mark(fc->ukrg);
}

static size_t Factory_memsize(const void *ptr)
{
    const msgpack_factory_t *fc = ptr;
    size_t total_size = sizeof(msgpack_factory_t);

    if (fc->ukrg) {
        total_size += sizeof(msgpack_unpacker_ext_registry_t) / (fc->ukrg->borrow_count + 1);
    }

    return total_size;
}

static const rb_data_type_t factory_data_type = {
    .wrap_struct_name = "msgpack:factory",
    .function = {
        .dmark = Factory_mark,
        .dfree = Factory_free,
        .dsize = Factory_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static inline msgpack_factory_t *Factory_get(VALUE object)
{
    msgpack_factory_t *factory;
    TypedData_Get_Struct(object, msgpack_factory_t, &factory_data_type, factory);
    if (!factory) {
        rb_raise(rb_eArgError, "Uninitialized Factory object");
    }
    return factory;
}

static VALUE Factory_alloc(VALUE klass)
{
    msgpack_factory_t *fc;
    return TypedData_Make_Struct(klass, msgpack_factory_t, &factory_data_type, fc);
}

static VALUE Factory_initialize(int argc, VALUE* argv, VALUE self)
{
    msgpack_factory_t *fc = Factory_get(self);

    msgpack_packer_ext_registry_init(self, &fc->pkrg);
    // fc->ukrg is lazily initialized

    fc->has_symbol_ext_type = false;

    switch (argc) {
    case 0:
        break;
    default:
        // TODO options is not supported yet
        rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)", argc);
    }

    return Qnil;
}

static VALUE Factory_dup(VALUE self)
{
    VALUE clone = Factory_alloc(rb_obj_class(self));

    msgpack_factory_t *fc = Factory_get(self);
    msgpack_factory_t *cloned_fc = Factory_get(clone);

    cloned_fc->has_symbol_ext_type = fc->has_symbol_ext_type;
    cloned_fc->pkrg = fc->pkrg;
    msgpack_unpacker_ext_registry_borrow(fc->ukrg, &cloned_fc->ukrg);
    msgpack_packer_ext_registry_dup(clone, &fc->pkrg, &cloned_fc->pkrg);

    return clone;
}

static VALUE Factory_freeze(VALUE self) {
    if(!rb_obj_frozen_p(self)) {
        msgpack_factory_t *fc = Factory_get(self);

        if (RTEST(fc->pkrg.hash)) {
            rb_hash_freeze(fc->pkrg.hash);
            if (!RTEST(fc->pkrg.cache)) {
                // If the factory is frozen, we can safely share the packer cache between
                // all packers. So we eagerly create it now so it's available when #packer
                // is called.
                RB_OBJ_WRITE(self, &fc->pkrg.cache, rb_hash_new());
            }
        }

        rb_obj_freeze(self);
    }

    return self;
}

VALUE MessagePack_Factory_packer(int argc, VALUE* argv, VALUE self)
{
    msgpack_factory_t *fc = Factory_get(self);

    VALUE packer = MessagePack_Packer_alloc(cMessagePack_Packer);
    MessagePack_Packer_initialize(argc, argv, packer);

    msgpack_packer_t* pk = MessagePack_Packer_get(packer);
    msgpack_packer_ext_registry_destroy(&pk->ext_registry);
    msgpack_packer_ext_registry_borrow(packer, &fc->pkrg, &pk->ext_registry);
    pk->has_bigint_ext_type = fc->has_bigint_ext_type;
    pk->has_symbol_ext_type = fc->has_symbol_ext_type;

    return packer;
}

VALUE MessagePack_Factory_unpacker(int argc, VALUE* argv, VALUE self)
{
    msgpack_factory_t *fc = Factory_get(self);

    VALUE unpacker = MessagePack_Unpacker_alloc(cMessagePack_Unpacker);
    MessagePack_Unpacker_initialize(argc, argv, unpacker);

    msgpack_unpacker_t* uk = MessagePack_Unpacker_get(unpacker);
    msgpack_unpacker_ext_registry_borrow(fc->ukrg, &uk->ext_registry);
    uk->optimized_symbol_ext_type = fc->optimized_symbol_ext_type;
    uk->symbol_ext_type = fc->symbol_ext_type;

    return unpacker;
}

static VALUE Factory_registered_types_internal(VALUE self)
{
    msgpack_factory_t *fc = Factory_get(self);

    VALUE uk_mapping = rb_hash_new();
    if (fc->ukrg) {
        for(int i=0; i < 256; i++) {
            if(!NIL_P(fc->ukrg->array[i])) {
                rb_hash_aset(uk_mapping, INT2FIX(i - 128), fc->ukrg->array[i]);
            }
        }
    }

    return rb_ary_new3(
        2,
        RTEST(fc->pkrg.hash) ? rb_hash_dup(fc->pkrg.hash) : rb_hash_new(),
        uk_mapping
    );
}

static VALUE Factory_register_type_internal(VALUE self, VALUE rb_ext_type, VALUE ext_module, VALUE options)
{
    msgpack_factory_t *fc = Factory_get(self);

    Check_Type(rb_ext_type, T_FIXNUM);

    if(rb_type(ext_module) != T_MODULE && rb_type(ext_module) != T_CLASS) {
        rb_raise(rb_eArgError, "expected Module/Class but found %s.", rb_obj_classname(ext_module));
    }

    int flags = 0;

    VALUE packer_proc = Qnil;
    VALUE unpacker_proc = Qnil;
    if(!NIL_P(options)) {
        Check_Type(options, T_HASH);
        packer_proc = rb_hash_aref(options, ID2SYM(rb_intern("packer")));
        unpacker_proc = rb_hash_aref(options, ID2SYM(rb_intern("unpacker")));
    }

    if (OBJ_FROZEN(self)) {
        rb_raise(rb_eFrozenError, "can't modify frozen MessagePack::Factory");
    }

    int ext_type = NUM2INT(rb_ext_type);
    if(ext_type < -128 || ext_type > 127) {
        rb_raise(rb_eRangeError, "integer %d too big to convert to `signed char'", ext_type);
    }

    if(ext_module == rb_cSymbol) {
        if(NIL_P(options) || RTEST(rb_hash_aref(options, ID2SYM(rb_intern("packer"))))) {
            fc->has_symbol_ext_type = true;
        }
        if(RTEST(options) && RTEST(rb_hash_aref(options, ID2SYM(rb_intern("optimized_symbols_parsing"))))) {
            fc->optimized_symbol_ext_type = true;
        }
    }

    if(RTEST(options)) {
        if(RTEST(rb_hash_aref(options, ID2SYM(rb_intern("oversized_integer_extension"))))) {
            if(ext_module == rb_cInteger) {
                fc->has_bigint_ext_type = true;
            } else {
                rb_raise(rb_eArgError, "oversized_integer_extension: true is only for Integer class");
            }
        }

        if(RTEST(rb_hash_aref(options, ID2SYM(rb_intern("recursive"))))) {
            flags |= MSGPACK_EXT_RECURSIVE;
        }
    }

    msgpack_packer_ext_registry_put(self, &fc->pkrg, ext_module, ext_type, flags, packer_proc);
    msgpack_unpacker_ext_registry_put(self, &fc->ukrg, ext_module, ext_type, flags, unpacker_proc);

    return Qnil;
}

void MessagePack_Factory_module_init(VALUE mMessagePack)
{
    cMessagePack_Factory = rb_define_class_under(mMessagePack, "Factory", rb_cObject);

    rb_define_alloc_func(cMessagePack_Factory, Factory_alloc);

    rb_define_method(cMessagePack_Factory, "initialize", Factory_initialize, -1);
    rb_define_method(cMessagePack_Factory, "dup", Factory_dup, 0);
    rb_define_method(cMessagePack_Factory, "freeze", Factory_freeze, 0);

    rb_define_method(cMessagePack_Factory, "packer", MessagePack_Factory_packer, -1);
    rb_define_method(cMessagePack_Factory, "unpacker", MessagePack_Factory_unpacker, -1);

    rb_define_private_method(cMessagePack_Factory, "registered_types_internal", Factory_registered_types_internal, 0);
    rb_define_private_method(cMessagePack_Factory, "register_type_internal", Factory_register_type_internal, 3);
}
