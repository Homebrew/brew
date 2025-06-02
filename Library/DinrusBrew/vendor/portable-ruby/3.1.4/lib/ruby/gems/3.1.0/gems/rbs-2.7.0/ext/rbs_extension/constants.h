#ifndef RBS__CONSTANTS_H
#define RBS__CONSTANTS_H

extern VALUE RBS;

extern VALUE RBS_AST;
extern VALUE RBS_AST_Annotation;
extern VALUE RBS_AST_Comment;
extern VALUE RBS_AST_TypeParam;

extern VALUE RBS_AST_Declarations;
extern VALUE RBS_AST_Declarations_Alias;
extern VALUE RBS_AST_Declarations_Class_Super;
extern VALUE RBS_AST_Declarations_Class;
extern VALUE RBS_AST_Declarations_Constant;
extern VALUE RBS_AST_Declarations_Global;
extern VALUE RBS_AST_Declarations_Interface;
extern VALUE RBS_AST_Declarations_Module_Self;
extern VALUE RBS_AST_Declarations_Module;

extern VALUE RBS_AST_Members;
extern VALUE RBS_AST_Members_Alias;
extern VALUE RBS_AST_Members_AttrAccessor;
extern VALUE RBS_AST_Members_AttrReader;
extern VALUE RBS_AST_Members_AttrWriter;
extern VALUE RBS_AST_Members_ClassInstanceVariable;
extern VALUE RBS_AST_Members_ClassVariable;
extern VALUE RBS_AST_Members_Extend;
extern VALUE RBS_AST_Members_Include;
extern VALUE RBS_AST_Members_InstanceVariable;
extern VALUE RBS_AST_Members_MethodDefinition;
extern VALUE RBS_AST_Members_Prepend;
extern VALUE RBS_AST_Members_Private;
extern VALUE RBS_AST_Members_Public;

extern VALUE RBS_MethodType;
extern VALUE RBS_Namespace;

extern VALUE RBS_ParsingError;
extern VALUE RBS_TypeName;

extern VALUE RBS_Types;
extern VALUE RBS_Types_Alias;
extern VALUE RBS_Types_Bases;
extern VALUE RBS_Types_Bases_Any;
extern VALUE RBS_Types_Bases_Bool;
extern VALUE RBS_Types_Bases_Bottom;
extern VALUE RBS_Types_Bases_Class;
extern VALUE RBS_Types_Bases_Instance;
extern VALUE RBS_Types_Bases_Nil;
extern VALUE RBS_Types_Bases_Self;
extern VALUE RBS_Types_Bases_Top;
extern VALUE RBS_Types_Bases_Void;
extern VALUE RBS_Types_Block;
extern VALUE RBS_Types_ClassInstance;
extern VALUE RBS_Types_ClassSingleton;
extern VALUE RBS_Types_Function_Param;
extern VALUE RBS_Types_Function;
extern VALUE RBS_Types_Interface;
extern VALUE RBS_Types_Intersection;
extern VALUE RBS_Types_Literal;
extern VALUE RBS_Types_Optional;
extern VALUE RBS_Types_Proc;
extern VALUE RBS_Types_Record;
extern VALUE RBS_Types_Tuple;
extern VALUE RBS_Types_Union;
extern VALUE RBS_Types_Variable;

void rbs__init_constants();

#endif
