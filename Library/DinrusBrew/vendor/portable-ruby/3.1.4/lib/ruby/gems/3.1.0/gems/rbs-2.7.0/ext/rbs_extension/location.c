#include "rbs_extension.h"

VALUE RBS_Location;

rbs_loc_list *rbs_loc_list_add(rbs_loc_list *list, const ID name, const range r) {
  rbs_loc_list *new = malloc(sizeof(rbs_loc_list));
  new->next = list;
  new->name = name;
  new->rg = r;
  return new;
}

rbs_loc_list *rbs_loc_list_dup(rbs_loc_list *list) {
  if (list) {
    return rbs_loc_list_add(rbs_loc_list_dup(list->next), list->name, list->rg);
  } else {
    return NULL;
  }
}

void rbs_loc_list_free(rbs_loc_list *list) {
  while (list) {
    rbs_loc_list *next = list->next;
    free(list);
    list = next;
  }
}

bool rbs_loc_list_find(const rbs_loc_list *list, ID name, range *rg) {
  while (list) {
    if (list->name == name) {
      *rg = list->rg;
      return true;
    }

    list = list->next;
  }

  return false;
}

size_t rbs_loc_list_size(const rbs_loc_list *list) {
  size_t size = 0;

  while (list) {
    size += 1;
    list = list->next;
  }

  return size;
}

position rbs_loc_position(int char_pos) {
  position pos = { 0, char_pos, -1, -1 };
  return pos;
}

position rbs_loc_position3(int char_pos, int line, int column) {
  position pos = { 0, char_pos, line, column };
  return pos;
}

void rbs_loc_add_required_child(rbs_loc *loc, ID name, range r) {
  loc->requireds = rbs_loc_list_add(loc->requireds, name, r);
}

void rbs_loc_add_optional_child(rbs_loc *loc, ID name, range r) {
  loc->optionals = rbs_loc_list_add(loc->optionals, name, r);
}

void rbs_loc_init(rbs_loc *loc, VALUE buffer, range rg) {
  loc->buffer = buffer;
  loc->rg = rg;
  loc->optionals = NULL;
  loc->requireds = NULL;
}

void rbs_loc_free(rbs_loc *loc) {
  rbs_loc_list_free(loc->optionals);
  rbs_loc_list_free(loc->requireds);
  ruby_xfree(loc);
}

static void rbs_loc_mark(void *ptr)
{
  rbs_loc *loc = ptr;
  rb_gc_mark(loc->buffer);
}

static size_t rbs_loc_memsize(const void *ptr) {
  const rbs_loc *loc = ptr;
  return sizeof(*loc) + (rbs_loc_list_size(loc->optionals) + rbs_loc_list_size(loc->requireds)) * sizeof(rbs_loc_list);
}

static rb_data_type_t location_type = {
  "RBS::Location",
  {rbs_loc_mark, (RUBY_DATA_FUNC)rbs_loc_free, rbs_loc_memsize},
  0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE location_s_allocate(VALUE klass) {
  rbs_loc *loc;
  VALUE obj = TypedData_Make_Struct(klass, rbs_loc, &location_type, loc);

  rbs_loc_init(loc, Qnil, NULL_RANGE);

  return obj;
}

rbs_loc *rbs_check_location(VALUE obj) {
  return rb_check_typeddata(obj, &location_type);
}

static VALUE location_initialize(VALUE self, VALUE buffer, VALUE start_pos, VALUE end_pos) {
  rbs_loc *loc = rbs_check_location(self);

  position start = rbs_loc_position(FIX2INT(start_pos));
  position end = rbs_loc_position(FIX2INT(end_pos));

  loc->buffer = buffer;
  loc->rg.start = start;
  loc->rg.end = end;

  return Qnil;
}

static VALUE location_initialize_copy(VALUE self, VALUE other) {
  rbs_loc *self_loc = rbs_check_location(self);
  rbs_loc *other_loc = rbs_check_location(other);

  self_loc->buffer = other_loc->buffer;
  self_loc->rg = other_loc->rg;
  self_loc->requireds = rbs_loc_list_dup(other_loc->requireds);
  self_loc->optionals = rbs_loc_list_dup(other_loc->optionals);

  return Qnil;
}

static VALUE location_buffer(VALUE self) {
  rbs_loc *loc = rbs_check_location(self);
  return loc->buffer;
}

static VALUE location_start_pos(VALUE self) {
  rbs_loc *loc = rbs_check_location(self);
  return INT2FIX(loc->rg.start.char_pos);
}

static VALUE location_end_pos(VALUE self) {
  rbs_loc *loc = rbs_check_location(self);
  return INT2FIX(loc->rg.end.char_pos);
}

static VALUE location_start_loc(VALUE self) {
  rbs_loc *loc = rbs_check_location(self);

  if (loc->rg.start.line >= 0) {
    VALUE pair = rb_ary_new_capa(2);
    rb_ary_push(pair, INT2FIX(loc->rg.start.line));
    rb_ary_push(pair, INT2FIX(loc->rg.start.column));
    return pair;
  } else {
    return Qnil;
  }
}

static VALUE location_end_loc(VALUE self) {
  rbs_loc *loc = rbs_check_location(self);

  if (loc->rg.end.line >= 0) {
    VALUE pair = rb_ary_new_capa(2);
    rb_ary_push(pair, INT2FIX(loc->rg.end.line));
    rb_ary_push(pair, INT2FIX(loc->rg.end.column));
    return pair;
  } else {
    return Qnil;
  }
}

static VALUE location_add_required_child(VALUE self, VALUE name, VALUE start, VALUE end) {
  rbs_loc *loc = rbs_check_location(self);

  range rg;
  rg.start = rbs_loc_position(FIX2INT(start));
  rg.end = rbs_loc_position(FIX2INT(end));

  rbs_loc_add_required_child(loc, SYM2ID(name), rg);

  return Qnil;
}

static VALUE location_add_optional_child(VALUE self, VALUE name, VALUE start, VALUE end) {
  rbs_loc *loc = rbs_check_location(self);

  range rg;
  rg.start = rbs_loc_position(FIX2INT(start));
  rg.end = rbs_loc_position(FIX2INT(end));

  rbs_loc_add_optional_child(loc, SYM2ID(name), rg);

  return Qnil;
}

static VALUE location_add_optional_no_child(VALUE self, VALUE name) {
  rbs_loc *loc = rbs_check_location(self);

  rbs_loc_add_optional_child(loc, SYM2ID(name), NULL_RANGE);

  return Qnil;
}

VALUE rbs_new_location(VALUE buffer, range rg) {
  rbs_loc *loc;
  VALUE obj = TypedData_Make_Struct(RBS_Location, rbs_loc, &location_type, loc);

  rbs_loc_init(loc, buffer, rg);

  return obj;
}

static VALUE location_aref(VALUE self, VALUE name) {
  rbs_loc *loc = rbs_check_location(self);

  range result;
  ID id = SYM2ID(name);

  if (rbs_loc_list_find(loc->requireds, id, &result)) {
    return rbs_new_location(loc->buffer, result);
  }

  if (rbs_loc_list_find(loc->optionals, id, &result)) {
    if (null_range_p(result)) {
      return Qnil;
    } else {
      return rbs_new_location(loc->buffer, result);
    }
  }

  VALUE string = rb_funcall(name, rb_intern("to_s"), 0);
  rb_raise(rb_eRuntimeError, "Unknown child name given: %s", RSTRING_PTR(string));
}

static VALUE location_optional_keys(VALUE self) {
  VALUE keys = rb_ary_new();

  rbs_loc *loc = rbs_check_location(self);
  rbs_loc_list *list = loc->optionals;

  while (list) {
    rb_ary_push(keys, ID2SYM(list->name));
    list = list->next;
  }

  return keys;
}

static VALUE location_required_keys(VALUE self) {
  VALUE keys = rb_ary_new();

  rbs_loc *loc = rbs_check_location(self);
  rbs_loc_list *list = loc->requireds;

  while (list) {
    rb_ary_push(keys, ID2SYM(list->name));
    list = list->next;
  }

  return keys;
}

VALUE rbs_location_pp(VALUE buffer, const position *start_pos, const position *end_pos) {
  range rg = { *start_pos, *end_pos };
  rg.start = *start_pos;
  rg.end = *end_pos;

  return rbs_new_location(buffer, rg);
}

void rbs__init_location(void) {
  RBS_Location = rb_define_class_under(RBS, "Location", rb_cObject);
  rb_define_alloc_func(RBS_Location, location_s_allocate);
  rb_define_private_method(RBS_Location, "initialize", location_initialize, 3);
  rb_define_private_method(RBS_Location, "initialize_copy", location_initialize_copy, 1);
  rb_define_method(RBS_Location, "buffer", location_buffer, 0);
  rb_define_method(RBS_Location, "start_pos", location_start_pos, 0);
  rb_define_method(RBS_Location, "end_pos", location_end_pos, 0);
  rb_define_private_method(RBS_Location, "_start_loc", location_start_loc, 0);
  rb_define_private_method(RBS_Location, "_end_loc", location_end_loc, 0);
  rb_define_method(RBS_Location, "_add_required_child", location_add_required_child, 3);
  rb_define_method(RBS_Location, "_add_optional_child", location_add_optional_child, 3);
  rb_define_method(RBS_Location, "_add_optional_no_child", location_add_optional_no_child, 1);
  rb_define_method(RBS_Location, "_optional_keys", location_optional_keys, 0);
  rb_define_method(RBS_Location, "_required_keys", location_required_keys, 0);
  rb_define_method(RBS_Location, "[]", location_aref, 1);
}
