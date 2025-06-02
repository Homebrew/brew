#include <ruby/ruby.h>

VALUE rb_iseqw_new(VALUE v);
void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);
size_t rb_obj_memsize_of(VALUE);

// implementation specific.
enum imemo_type {
    imemo_iseq = 7,
    imemo_mask = 0x07
};

static inline enum imemo_type
imemo_type(VALUE imemo)
{
    return (RBASIC(imemo)->flags >> FL_USHIFT) & imemo_mask;
}

static inline int
rb_obj_is_iseq(VALUE iseq)
{
    return RB_TYPE_P(iseq, T_IMEMO) && imemo_type(iseq) == imemo_iseq;
}

struct iseq_i_data {
    void (*func)(VALUE v, void *data);
    void *data;
};

int
iseq_i(void *vstart, void *vend, size_t stride, void *ptr)
{
    VALUE v;
    struct iseq_i_data *data = (struct iseq_i_data *)ptr;

    for (v = (VALUE)vstart; v != (VALUE)vend; v += stride) {
	if (RBASIC(v)->flags) {
	    switch (BUILTIN_TYPE(v)) {
	      case T_IMEMO:
		if (rb_obj_is_iseq(v)) {
		    data->func(v, data->data);
		}
		continue;
	      default:
		continue;
	    }
	}
    }

    return 0;
}

static void
each_iseq_i(VALUE v, void *ptr)
{
    rb_yield(rb_iseqw_new(v));
}

static VALUE
each_iseq(VALUE self)
{
    struct iseq_i_data data = {each_iseq_i, NULL};
    rb_objspace_each_objects(iseq_i, &data);
    return Qnil;
}

static void
count_iseq_i(VALUE v, void *ptr)
{
    size_t *sizep = (size_t *)ptr;
    *sizep += 1;
}

static VALUE
count_iseq(VALUE self)
{
    size_t size = 0;
    struct iseq_i_data data = {count_iseq_i, &size};
    rb_objspace_each_objects(iseq_i, &data);
    return SIZET2NUM(size);
}

void
Init_iseq_collector(void)
{
    VALUE rb_mObjSpace = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
    rb_define_singleton_method(rb_mObjSpace, "each_iseq", each_iseq, 0);
    rb_define_singleton_method(rb_mObjSpace, "count_iseq", count_iseq, 0);
}
