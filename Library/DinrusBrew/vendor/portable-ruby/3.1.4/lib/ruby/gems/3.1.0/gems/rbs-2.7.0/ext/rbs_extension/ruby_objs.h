#ifndef RBS__RUBY_OBJS_H
#define RBS__RUBY_OBJS_H

#include "ruby.h"

VALUE rbs_alias(VALUE typename, VALUE args, VALUE location);
VALUE rbs_ast_annotation(VALUE string, VALUE location);
VALUE rbs_ast_comment(VALUE string, VALUE location);
VALUE rbs_ast_type_param(VALUE name, VALUE variance, bool unchecked, VALUE upper_bound, VALUE location);
VALUE rbs_ast_decl_alias(VALUE name, VALUE type_params, VALUE type, VALUE annotations, VALUE location, VALUE comment);
VALUE rbs_ast_decl_class_super(VALUE name, VALUE args, VALUE location);
VALUE rbs_ast_decl_class(VALUE name, VALUE type_params, VALUE super_class, VALUE members, VALUE annotations, VALUE location, VALUE comment);
VALUE rbs_ast_decl_constant(VALUE name, VALUE type, VALUE location, VALUE comment);
VALUE rbs_ast_decl_global(VALUE name, VALUE type, VALUE location, VALUE comment);
VALUE rbs_ast_decl_interface(VALUE name, VALUE type_params, VALUE members, VALUE annotations, VALUE location, VALUE comment);
VALUE rbs_ast_decl_module_self(VALUE name, VALUE args, VALUE location);
VALUE rbs_ast_decl_module(VALUE name, VALUE type_params, VALUE self_types, VALUE members, VALUE annotations, VALUE location, VALUE comment);
VALUE rbs_ast_members_alias(VALUE new_name, VALUE old_name, VALUE kind, VALUE annotations, VALUE location, VALUE comment);
VALUE rbs_ast_members_attribute(VALUE klass, VALUE name, VALUE type, VALUE ivar_name, VALUE kind, VALUE annotations, VALUE location, VALUE comment, VALUE visibility);
VALUE rbs_ast_members_method_definition(VALUE name, VALUE kind, VALUE types, VALUE annotations, VALUE location, VALUE comment, VALUE overload, VALUE visibility);
VALUE rbs_ast_members_mixin(VALUE klass, VALUE name, VALUE args, VALUE annotations, VALUE location, VALUE comment);
VALUE rbs_ast_members_variable(VALUE klass, VALUE name, VALUE type, VALUE location, VALUE comment);
VALUE rbs_ast_members_visibility(VALUE klass, VALUE location);
VALUE rbs_base_type(VALUE klass, VALUE location);
VALUE rbs_block(VALUE type, VALUE required, VALUE self_type);
VALUE rbs_class_instance(VALUE typename, VALUE type_args, VALUE location);
VALUE rbs_class_singleton(VALUE typename, VALUE location);
VALUE rbs_function_param(VALUE type, VALUE name, VALUE location);
VALUE rbs_function(VALUE required_positional_params, VALUE optional_positional_params, VALUE rest_positional_params, VALUE trailing_positional_params, VALUE required_keywords, VALUE optional_keywords, VALUE rest_keywords, VALUE return_type);
VALUE rbs_interface(VALUE typename, VALUE type_args, VALUE location);
VALUE rbs_intersection(VALUE types, VALUE location);
VALUE rbs_literal(VALUE literal, VALUE location);
VALUE rbs_method_type(VALUE type_params, VALUE type, VALUE block, VALUE location);
VALUE rbs_namespace(VALUE path, VALUE absolute);
VALUE rbs_optional(VALUE type, VALUE location);
VALUE rbs_proc(VALUE function, VALUE block, VALUE location, VALUE self_type);
VALUE rbs_record(VALUE fields, VALUE location);
VALUE rbs_tuple(VALUE types, VALUE location);
VALUE rbs_type_name(VALUE namespace, VALUE name);
VALUE rbs_union(VALUE types, VALUE location);
VALUE rbs_variable(VALUE name, VALUE location);

#endif
