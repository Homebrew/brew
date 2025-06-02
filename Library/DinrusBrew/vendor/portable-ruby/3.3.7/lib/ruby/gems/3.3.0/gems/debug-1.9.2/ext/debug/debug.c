
#include "ruby/ruby.h"
#include "ruby/debug.h"
#include "ruby/encoding.h"
#include "debug_version.h"
//
static VALUE rb_mDebugger;

// iseq
typedef struct rb_iseq_struct rb_iseq_t;
const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);
VALUE rb_iseq_realpath(const rb_iseq_t *iseq);

static VALUE
iseq_realpath(VALUE iseqw)
{
    return rb_iseq_realpath(rb_iseqw_to_iseq(iseqw));
}

static VALUE rb_cFrameInfo;

static VALUE
di_entry(VALUE loc, VALUE self, VALUE binding, VALUE iseq, VALUE klass, VALUE depth)
{
    return rb_struct_new(rb_cFrameInfo,
                         // :location, :self, :binding, :iseq, :class, :frame_depth,
                         loc, self, binding, iseq, klass, depth,
                         // :has_return_value, :return_value,
                         Qnil, Qnil,
                         // :has_raised_exception, :raised_exception,
                         Qnil, Qnil,
                         // :show_line, :local_variables
                         Qnil,
                         // :_local_variables, :_callee # for recorder
                         Qnil, Qnil,
                         // :dupped_binding
                         Qnil
                         );
}

static int
str_start_with(VALUE str, VALUE prefix)
{
    StringValue(prefix);
    rb_enc_check(str, prefix);
    if (RSTRING_LEN(str) >= RSTRING_LEN(prefix) &&
        memcmp(RSTRING_PTR(str), RSTRING_PTR(prefix), RSTRING_LEN(prefix)) == 0) {
        return 1;
    }
    else {
        return 0;
    }
}

static VALUE
di_body(const rb_debug_inspector_t *dc, void *ptr)
{
    VALUE skip_path_prefix = (VALUE)ptr;
    VALUE locs = rb_debug_inspector_backtrace_locations(dc);
    VALUE ary = rb_ary_new();
    long len = RARRAY_LEN(locs);
    long i;

    for (i=1; i<len; i++) {
        VALUE e;
        VALUE iseq = rb_debug_inspector_frame_iseq_get(dc, i);
        VALUE loc = RARRAY_AREF(locs, i);
        VALUE path;

        if (!NIL_P(iseq)) {
            path = iseq_realpath(iseq);
        }
        else {
            // C frame
            path = rb_funcall(loc, rb_intern("path"), 0);
        }

        if (!NIL_P(path) && !NIL_P(skip_path_prefix) && str_start_with(path, skip_path_prefix)) {
            continue;
        }

        e = di_entry(loc,
                     rb_debug_inspector_frame_self_get(dc, i),
                     rb_debug_inspector_frame_binding_get(dc, i),
                     iseq,
                     rb_debug_inspector_frame_class_get(dc, i),
#ifdef RB_DEBUG_INSPECTOR_FRAME_DEPTH
                     rb_debug_inspector_frame_depth(dc, i)
#else
                     INT2FIX(len - i)
#endif
                     );
        rb_ary_push(ary, e);
    }

    return ary;
}

static VALUE
capture_frames(VALUE self, VALUE skip_path_prefix)
{
    return rb_debug_inspector_open(di_body, (void *)skip_path_prefix);
}

#ifdef RB_DEBUG_INSPECTOR_FRAME_DEPTH
static VALUE
frame_depth(VALUE self)
{
    return rb_debug_inspector_current_depth();
}
#else
static VALUE
frame_depth(VALUE self)
{
    // TODO: more efficient API
    VALUE bt = rb_make_backtrace();
    return INT2FIX(RARRAY_LEN(bt));
}
#endif


// iseq

const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);

#ifdef HAVE_RB_ISEQ_TYPE
VALUE rb_iseq_type(const rb_iseq_t *);

static VALUE
iseq_type(VALUE iseqw)
{
    const rb_iseq_t *iseq = rb_iseqw_to_iseq(iseqw);
    return rb_iseq_type(iseq);
}
#endif

#ifdef HAVE_RB_ISEQ_PARAMETERS
VALUE rb_iseq_parameters(const rb_iseq_t *, int is_proc);

static VALUE
iseq_parameters_symbols(VALUE iseqw)
{
    const rb_iseq_t *iseq = rb_iseqw_to_iseq(iseqw);
    VALUE params = rb_iseq_parameters(iseq, 0);
    VALUE ary = rb_ary_new();

    static VALUE sym_ast, sym_astast, sym_amp;

    if (sym_ast == 0) {
        sym_ast = ID2SYM(rb_intern("*"));
        sym_astast = ID2SYM(rb_intern("**"));
        sym_amp = ID2SYM(rb_intern("&"));
    }

    for (long i=0; i<RARRAY_LEN(params); i++) {
        VALUE e = RARRAY_AREF(params, i);
        if (RARRAY_LEN(e) == 2) {
            VALUE sym = RARRAY_AREF(e, 1);
            if (sym != sym_ast &&
                sym != sym_astast &&
                sym != sym_amp) rb_ary_push(ary, RARRAY_AREF(e, 1));
        }
    }

    return ary;
}
#endif

#ifdef HAVE_RB_ISEQ_CODE_LOCATION
void rb_iseq_code_location(const rb_iseq_t *, int *first_lineno, int *first_column, int *last_lineno, int *last_column);

static VALUE
iseq_first_line(VALUE iseqw)
{
    const rb_iseq_t *iseq = rb_iseqw_to_iseq(iseqw);
    int line;
    rb_iseq_code_location(iseq, &line, NULL, NULL, NULL);
    return INT2NUM(line);
}

static VALUE
iseq_last_line(VALUE iseqw)
{
    const rb_iseq_t *iseq = rb_iseqw_to_iseq(iseqw);
    int line;
    rb_iseq_code_location(iseq, NULL, NULL, &line, NULL);
    return INT2NUM(line);
}
#endif

#ifdef HAVE_RB_ISEQ
void Init_iseq_collector(void);
#endif

void
Init_debug(void)
{
#ifdef HAVE_RB_ISEQ
    VALUE rb_mRubyVM = rb_const_get(rb_cObject, rb_intern("RubyVM"));
    VALUE rb_cISeq = rb_const_get(rb_mRubyVM, rb_intern("InstructionSequence"));
#endif
    rb_mDebugger = rb_const_get(rb_cObject, rb_intern("DEBUGGER__"));
    rb_cFrameInfo = rb_const_get(rb_mDebugger, rb_intern("FrameInfo"));

    // Debugger and FrameInfo were defined in Ruby. We need to register them
    // as mark objects so they are automatically pinned.
    rb_gc_register_mark_object(rb_mDebugger);
    rb_gc_register_mark_object(rb_cFrameInfo);
    rb_define_singleton_method(rb_mDebugger, "capture_frames", capture_frames, 1);
    rb_define_singleton_method(rb_mDebugger, "frame_depth", frame_depth, 0);
    rb_define_const(rb_mDebugger, "SO_VERSION", rb_str_new2(RUBY_DEBUG_VERSION));

    // iseq
#ifdef HAVE_RB_ISEQ_TYPE
    rb_define_method(rb_cISeq, "type", iseq_type, 0);
#endif
#ifdef HAVE_RB_ISEQ_PARAMETERS
    rb_define_method(rb_cISeq, "parameters_symbols", iseq_parameters_symbols, 0);
#endif
#ifdef HAVE_RB_ISEQ_CODE_LOCATION
    rb_define_method(rb_cISeq, "first_line", iseq_first_line, 0);
    rb_define_method(rb_cISeq, "last_line", iseq_last_line, 0);
#endif

#ifdef HAVE_RB_ISEQ
    Init_iseq_collector();
#endif
}
