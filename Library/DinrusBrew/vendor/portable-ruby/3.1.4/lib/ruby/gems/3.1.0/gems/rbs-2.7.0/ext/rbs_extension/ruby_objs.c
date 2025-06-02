#include "rbs_extension.h"

#ifdef RB_PASS_KEYWORDS
  // Ruby 2.7 or later
  #define CLASS_NEW_INSTANCE(klass, argc, argv)\
          rb_class_new_instance_kw(argc, argv, klass, RB_PASS_KEYWORDS)
#else
  // Ruby 2.6
  #define CLASS_NEW_INSTANCE(receiver, argc, argv)\
          rb_class_new_instance(argc, argv, receiver)
#endif

VALUE rbs_base_type(VALUE klass, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    klass,
    1,
    &args
  );
}

VALUE rbs_namespace(VALUE path, VALUE absolute) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("path")), path);
  rb_hash_aset(args, ID2SYM(rb_intern("absolute")), absolute);

  return CLASS_NEW_INSTANCE(
    RBS_Namespace,
    1,
    &args
  );
}

VALUE rbs_type_name(VALUE namespace, VALUE name) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("namespace")), namespace);
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);

  return CLASS_NEW_INSTANCE(
    RBS_TypeName,
    1,
    &args
  );
}

VALUE rbs_class_instance(VALUE typename, VALUE type_args, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), typename);
  rb_hash_aset(args, ID2SYM(rb_intern("args")), type_args);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_ClassInstance,
    1,
    &args
  );
}

VALUE rbs_class_singleton(VALUE typename, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), typename);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_ClassSingleton,
    1,
    &args
  );
}

VALUE rbs_alias(VALUE typename, VALUE args, VALUE location) {
  VALUE kwargs = rb_hash_new();
  rb_hash_aset(kwargs, ID2SYM(rb_intern("name")), typename);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("args")), args);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Alias,
    1,
    &kwargs
  );
}

VALUE rbs_interface(VALUE typename, VALUE type_args, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), typename);
  rb_hash_aset(args, ID2SYM(rb_intern("args")), type_args);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Interface,
    1,
    &args
  );
}

VALUE rbs_union(VALUE types, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("types")), types);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Union,
    1,
    &args
  );
}

VALUE rbs_intersection(VALUE types, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("types")), types);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Intersection,
    1,
    &args
  );
}

VALUE rbs_tuple(VALUE types, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("types")), types);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Tuple,
    1,
    &args
  );
}

VALUE rbs_optional(VALUE type, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Optional,
    1,
    &args
  );
}

VALUE rbs_block(VALUE type, VALUE required, VALUE self_type) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("required")), required);
  rb_hash_aset(args, ID2SYM(rb_intern("self_type")), self_type);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Block,
    1,
    &args
  );
}

VALUE rbs_function_param(VALUE type, VALUE name, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Function_Param,
    1,
    &args
  );
}

VALUE rbs_function(
  VALUE required_positional_params,
  VALUE optional_positional_params,
  VALUE rest_positional_param,
  VALUE trailing_positional_params,
  VALUE required_keyword_params,
  VALUE optional_keyword_params,
  VALUE rest_keyword_param,
  VALUE return_type
) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("required_positionals")), required_positional_params);
  rb_hash_aset(args, ID2SYM(rb_intern("optional_positionals")), optional_positional_params);
  rb_hash_aset(args, ID2SYM(rb_intern("rest_positionals")), rest_positional_param);
  rb_hash_aset(args, ID2SYM(rb_intern("trailing_positionals")), trailing_positional_params);
  rb_hash_aset(args, ID2SYM(rb_intern("required_keywords")), required_keyword_params);
  rb_hash_aset(args, ID2SYM(rb_intern("optional_keywords")), optional_keyword_params);
  rb_hash_aset(args, ID2SYM(rb_intern("rest_keywords")), rest_keyword_param);
  rb_hash_aset(args, ID2SYM(rb_intern("return_type")), return_type);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Function,
    1,
    &args
  );
}

VALUE rbs_proc(VALUE function, VALUE block, VALUE location, VALUE self_type) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("type")), function);
  rb_hash_aset(args, ID2SYM(rb_intern("block")), block);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("self_type")), self_type);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Proc,
    1,
    &args
  );
}

VALUE rbs_void(VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Bases_Void,
    1,
    &args
  );
}

VALUE rbs_literal(VALUE literal, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("literal")), literal);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Literal,
    1,
    &args
  );
}

VALUE rbs_record(VALUE fields, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("fields")), fields);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Record,
    1,
    &args
  );
}

VALUE rbs_variable(VALUE name, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);

  return CLASS_NEW_INSTANCE(
    RBS_Types_Variable,
    1,
    &args
  );
}

VALUE rbs_method_type(VALUE type_params, VALUE type, VALUE block, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("type_params")), type_params);
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("block")), block);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_MethodType,
    1,
    &args
  );
}

VALUE rbs_ast_comment(VALUE string, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("string")), string);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Comment,
    1,
    &args
  );
}

VALUE rbs_ast_annotation(VALUE string, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("string")), string);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Annotation,
    1,
    &args
  );
}

VALUE rbs_ast_type_param(VALUE name, VALUE variance, bool unchecked, VALUE upper_bound, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("variance")), variance);
  rb_hash_aset(args, ID2SYM(rb_intern("upper_bound")), upper_bound);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  VALUE type_param = CLASS_NEW_INSTANCE(RBS_AST_TypeParam, 1, &args);

  if (unchecked) {
    rb_funcall(type_param, rb_intern("unchecked!"), 0);
  }

  return type_param;
}

VALUE rbs_ast_decl_constant(VALUE name, VALUE type, VALUE location, VALUE comment) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Declarations_Constant,
    1,
    &args
  );
}

VALUE rbs_ast_decl_global(VALUE name, VALUE type, VALUE location, VALUE comment) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Declarations_Global,
    1,
    &args
  );
}

VALUE rbs_ast_decl_alias(VALUE name, VALUE type_params, VALUE type, VALUE annotations, VALUE location, VALUE comment) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("type_params")), type_params);
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("annotations")), annotations);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Declarations_Alias,
    1,
    &args
  );
}

VALUE rbs_ast_decl_interface(VALUE name, VALUE type_params, VALUE members, VALUE annotations, VALUE location, VALUE comment) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("type_params")), type_params);
  rb_hash_aset(args, ID2SYM(rb_intern("members")), members);
  rb_hash_aset(args, ID2SYM(rb_intern("annotations")), annotations);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Declarations_Interface,
    1,
    &args
  );
}

VALUE rbs_ast_decl_module_self(VALUE name, VALUE args, VALUE location) {
  VALUE kw_args = rb_hash_new();
  rb_hash_aset(kw_args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(kw_args, ID2SYM(rb_intern("args")), args);
  rb_hash_aset(kw_args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Declarations_Module_Self,
    1,
    &kw_args
  );
}

VALUE rbs_ast_decl_module(VALUE name, VALUE type_params, VALUE self_types, VALUE members, VALUE annotations, VALUE location, VALUE comment) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("type_params")), type_params);
  rb_hash_aset(args, ID2SYM(rb_intern("self_types")), self_types);
  rb_hash_aset(args, ID2SYM(rb_intern("members")), members);
  rb_hash_aset(args, ID2SYM(rb_intern("annotations")), annotations);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Declarations_Module,
    1,
    &args
  );
}

VALUE rbs_ast_members_method_definition(VALUE name, VALUE kind, VALUE types, VALUE annotations, VALUE location, VALUE comment, VALUE overload, VALUE visibility) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("kind")), kind);
  rb_hash_aset(args, ID2SYM(rb_intern("types")), types);
  rb_hash_aset(args, ID2SYM(rb_intern("annotations")), annotations);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);
  rb_hash_aset(args, ID2SYM(rb_intern("overload")), overload);
  rb_hash_aset(args, ID2SYM(rb_intern("visibility")), visibility);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Members_MethodDefinition,
    1,
    &args
  );
}

VALUE rbs_ast_members_variable(VALUE klass, VALUE name, VALUE type, VALUE location, VALUE comment) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    klass,
    1,
    &args
  );
}

VALUE rbs_ast_members_mixin(VALUE klass, VALUE name, VALUE module_args, VALUE annotations, VALUE location, VALUE comment) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("args")), module_args);
  rb_hash_aset(args, ID2SYM(rb_intern("annotations")), annotations);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    klass,
    1,
    &args
  );
}

VALUE rbs_ast_members_attribute(VALUE klass, VALUE name, VALUE type, VALUE ivar_name, VALUE kind, VALUE annotations, VALUE location, VALUE comment, VALUE visibility) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(args, ID2SYM(rb_intern("type")), type);
  rb_hash_aset(args, ID2SYM(rb_intern("ivar_name")), ivar_name);
  rb_hash_aset(args, ID2SYM(rb_intern("kind")), kind);
  rb_hash_aset(args, ID2SYM(rb_intern("annotations")), annotations);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);
  rb_hash_aset(args, ID2SYM(rb_intern("visibility")), visibility);

  return CLASS_NEW_INSTANCE(
    klass,
    1,
    &args
  );
}

VALUE rbs_ast_members_visibility(VALUE klass, VALUE location) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    klass,
    1,
    &args
  );
}

VALUE rbs_ast_members_alias(VALUE new_name, VALUE old_name, VALUE kind, VALUE annotations, VALUE location, VALUE comment) {
  VALUE args = rb_hash_new();
  rb_hash_aset(args, ID2SYM(rb_intern("new_name")), new_name);
  rb_hash_aset(args, ID2SYM(rb_intern("old_name")), old_name);
  rb_hash_aset(args, ID2SYM(rb_intern("kind")), kind);
  rb_hash_aset(args, ID2SYM(rb_intern("annotations")), annotations);
  rb_hash_aset(args, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(args, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Members_Alias,
    1,
    &args
  );
}

VALUE rbs_ast_decl_class_super(VALUE name, VALUE args, VALUE location) {
  VALUE kwargs = rb_hash_new();
  rb_hash_aset(kwargs, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("args")), args);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("location")), location);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Declarations_Class_Super,
    1,
    &kwargs
  );
}

VALUE rbs_ast_decl_class(VALUE name, VALUE type_params, VALUE super_class, VALUE members, VALUE annotations, VALUE location, VALUE comment) {
  VALUE kwargs = rb_hash_new();
  rb_hash_aset(kwargs, ID2SYM(rb_intern("name")), name);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("type_params")), type_params);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("super_class")), super_class);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("members")), members);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("annotations")), annotations);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("location")), location);
  rb_hash_aset(kwargs, ID2SYM(rb_intern("comment")), comment);

  return CLASS_NEW_INSTANCE(
    RBS_AST_Declarations_Class,
    1,
    &kwargs
  );
}
