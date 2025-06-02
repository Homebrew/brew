# frozen_string_literal: true

module RBS
  module MethodNameHelper
    def method_name_string()
      separator = case kind
                  when :instance
                    "#"
                  when :singleton
                    "."
                  else
                    raise
                  end

      "#{type_name}#{separator}#{method_name}"
    end
  end

  class BaseError < StandardError; end
  class LoadingError < BaseError; end
  class DefinitionError < BaseError; end

  class ParsingError < BaseError
    attr_reader :location
    attr_reader :error_message
    attr_reader :token_type

    def initialize(location, error_message, token_type)
      @location = location
      @error_message = error_message
      @token_type = token_type

      super "#{Location.to_string location}: Syntax error: #{error_message}, token=`#{location.source}` (#{token_type})"
    end

    def error_value
      RBS.print_warning {
        "#{self.class.name}#error_value is deprecated and will be deleted in RBS 2.0. Consider using `location.source` instead."
      }
      location.source
    end

    def token_str
      RBS.print_warning {
        "#{self.class.name}#token_str is deprecated and will be deleted in RBS 2.0. Consider using `token_type` instead."
      }
      token_type
    end
  end

  class InvalidTypeApplicationError < DefinitionError
    attr_reader :type_name
    attr_reader :args
    attr_reader :params
    attr_reader :location

    def initialize(type_name:, args:, params:, location:)
      @type_name = type_name
      @args = args
      @params = params
      @location = location
      super "#{Location.to_string location}: #{type_name} expects parameters [#{params.join(", ")}], but given args [#{args.join(", ")}]"
    end

    def self.check!(type_name:, args:, params:, location:)
      unless args.size == params.size
        raise new(type_name: type_name, args: args, params: params, location: location)
      end
    end
  end

  class RecursiveAncestorError < DefinitionError
    attr_reader :ancestors
    attr_reader :location

    def initialize(ancestors:, location:)
      @ancestors = ancestors
      @location = location

      names = ancestors.map do |ancestor|
        case ancestor
        when Definition::Ancestor::Singleton
          "singleton(#{ancestor.name})"
        when Definition::Ancestor::Instance
          if ancestor.args.empty?
            ancestor.name.to_s
          else
            "#{ancestor.name}[#{ancestor.args.join(", ")}]"
          end
        end
      end

      super "#{Location.to_string location}: Detected recursive ancestors: #{names.join(" < ")}"
    end

    def self.check!(self_ancestor, ancestors:, location:)
      case self_ancestor
      when Definition::Ancestor::Instance
        if ancestors.any? {|a| a.is_a?(Definition::Ancestor::Instance) && a.name == self_ancestor.name }
          raise new(ancestors: ancestors + [self_ancestor], location: location)
        end
      when Definition::Ancestor::Singleton
        if ancestors.include?(self_ancestor)
          raise new(ancestors: ancestors + [self_ancestor], location: location)
        end
      end
    end
  end

  class NoTypeFoundError < BaseError
    attr_reader :type_name
    attr_reader :location

    def initialize(type_name:, location:)
      @type_name = type_name
      @location = location

      super "#{Location.to_string location}: Could not find #{type_name}"
    end

    def self.check!(type_name, env:, location:)
      dic = case
            when type_name.class?
              env.class_decls
            when type_name.alias?
              env.alias_decls
            when type_name.interface?
              env.interface_decls
            else
              raise
            end

      dic.key?(type_name) or raise new(type_name: type_name, location: location)

      type_name
    end
  end

  class NoSuperclassFoundError < DefinitionError
    attr_reader :type_name
    attr_reader :location

    def initialize(type_name:, location:)
      @type_name = type_name
      @location = location

      super "#{Location.to_string location}: Could not find super class: #{type_name}"
    end

    def self.check!(type_name, env:, location:)
      env.class_decls.key?(type_name) or raise new(type_name: type_name, location: location)
    end
  end

  class NoSelfTypeFoundError < DefinitionError
    attr_reader :type_name
    attr_reader :location

    def initialize(type_name:, location:)
      @type_name = type_name
      @location = location

      super "#{Location.to_string location}: Could not find self type: #{type_name}"
    end

    def self.check!(self_type, env:)
      type_name = self_type.name

      dic = case
            when type_name.class?
              env.class_decls
            when type_name.interface?
              env.interface_decls
            else
              raise
            end

      dic.key?(type_name) or raise new(type_name: type_name, location: self_type.location)
    end
  end

  class NoMixinFoundError < DefinitionError
    attr_reader :type_name
    attr_reader :member

    def initialize(type_name:, member:)
      @type_name = type_name
      @member = member

      super "#{Location.to_string location}: Could not find mixin: #{type_name}"
    end

    def location
      member.location
    end

    def self.check!(type_name, env:, member:)
      dic = case
            when type_name.class?
              env.class_decls
            when type_name.interface?
              env.interface_decls
            else
              raise
            end

      dic.key?(type_name) or raise new(type_name: type_name, member: member)
    end
  end

  class DuplicatedMethodDefinitionError < DefinitionError
    attr_reader :type
    attr_reader :method_name
    attr_reader :members

    def initialize(type:, method_name:, members:)
      @type = type
      @method_name = method_name
      @members = members

      message = +"#{Location.to_string location}: #{qualified_method_name} has duplicated definitions"
      if members.size > 1
        message << " in #{other_locations.map { |loc| Location.to_string loc }.join(', ')}"
      end
      super message
    end

    def qualified_method_name
      case type
      when Types::ClassSingleton
        "#{type.name}.#{method_name}"
      else
        "#{type.name}##{method_name}"
      end
    end

    def type_name
      type.name
    end

    def location
      members[0].location
    end

    def other_locations
      members.drop(1).map(&:location)
    end
  end

  class DuplicatedInterfaceMethodDefinitionError < DefinitionError
    attr_reader :type
    attr_reader :method_name
    attr_reader :member

    def initialize(type:, method_name:, member:)
      @type = type
      @method_name = method_name
      @member = member

      super "#{member.location}: Duplicated method definition: #{qualified_method_name}"
    end

    def qualified_method_name
      case type
      when Types::ClassSingleton
        "#{type.name}.#{method_name}"
      else
        "#{type.name}##{method_name}"
      end
    end

    def type_name
      type.name
    end
  end

  class UnknownMethodAliasError < DefinitionError
    attr_reader :type_name
    attr_reader :original_name
    attr_reader :aliased_name
    attr_reader :location

    def initialize(type_name:, original_name:, aliased_name:, location:)
      @type_name = type_name
      @original_name = original_name
      @aliased_name = aliased_name
      @location = location

      super "#{Location.to_string location}: Unknown method alias name: #{original_name} => #{aliased_name} (#{type_name})"
    end
  end

  class SuperclassMismatchError < DefinitionError
    attr_reader :name
    attr_reader :entry

    def initialize(name:, entry:)
      @name = name
      @entry = entry
      super "#{Location.to_string entry.primary.decl.location}: Superclass mismatch: #{name}"
    end
  end

  class InvalidOverloadMethodError < DefinitionError
    attr_reader :type_name
    attr_reader :method_name
    attr_reader :kind
    attr_reader :members

    def initialize(type_name:, method_name:, kind:, members:)
      @type_name = type_name
      @method_name = method_name
      @kind = kind
      @members = members

      delimiter = case kind
                  when :instance
                    "#"
                  when :singleton
                    "."
                  end

      super "#{Location.to_string members[0].location}: Invalid method overloading: #{type_name}#{delimiter}#{method_name}"
    end
  end

  class GenericParameterMismatchError < LoadingError
    attr_reader :name
    attr_reader :decl

    def initialize(name:, decl:)
      @name = name
      @decl = decl
      super "#{Location.to_string decl.location}: Generic parameters mismatch: #{name}"
    end
  end

  class DuplicatedDeclarationError < LoadingError
    attr_reader :name
    attr_reader :decls

    def initialize(name, *decls)
      @name = name
      @decls = decls

      last_decl = decls.last or raise
      super "#{Location.to_string last_decl.location}: Duplicated declaration: #{name}"
    end
  end

  class InvalidVarianceAnnotationError < DefinitionError
    attr_reader :type_name
    attr_reader :param
    attr_reader :location

    def initialize(type_name:, param:, location:)
      @type_name = type_name
      @param = param
      @location = location

      super "#{Location.to_string location}: Type parameter variance error: #{param.name} is #{param.variance} but used as incompatible variance"
    end
  end

  class RecursiveAliasDefinitionError < DefinitionError
    attr_reader :type
    attr_reader :defs

    def initialize(type:, defs:)
      @type = type
      @defs = defs

      super "#{Location.to_string location}: Recursive aliases in #{type}: #{defs.map(&:name).join(", ")}"
    end

    def location
      first_def = defs.first or raise
      original = first_def.original or raise
      original.location
    end
  end

  class MixinClassError < DefinitionError
    attr_reader :type_name
    attr_reader :member

    def initialize(type_name:, member:)
      @type_name = type_name
      @member = member

      super "#{Location.to_string member.location}: Cannot #{mixin_name} a class `#{member.name}` in the definition of `#{type_name}`"
    end

    def location
      member.location
    end

    def self.check!(type_name:, env:, member:)
      case env.class_decls[member.name]
      when Environment::ClassEntry
        raise new(type_name: type_name, member: member)
      end
    end

    private

    def mixin_name
      case member
      when AST::Members::Prepend
        "prepend"
      when AST::Members::Include
        "include"
      when AST::Members::Extend
        "extend"
      else
        raise
      end
    end
  end

  class RecursiveTypeAliasError < BaseError
    attr_reader :alias_names
    attr_reader :location

    def initialize(alias_names:, location:)
      @alias_names = alias_names
      @location = location

      super "#{Location.to_string location}: Recursive type alias definition found for: #{name}"
    end

    def name
      @alias_names.map(&:name).join(', ')
    end
  end

  class NonregularTypeAliasError < BaseError
    attr_reader :diagnostic
    attr_reader :location

    def initialize(diagnostic:, location:)
      @diagnostic = diagnostic
      @location = location

      super "#{Location.to_string location}: Nonregular generic type alias is prohibited: #{diagnostic.type_name}, #{diagnostic.nonregular_type}"
    end
  end

  class CyclicTypeParameterBound < BaseError
    attr_reader :params, :type_name, :method_name, :location

    def initialize(type_name:, method_name:, params:, location:)
      @type_name = type_name
      @method_name = method_name
      @params = params
      @location = location

      super "#{Location.to_string(location)}: Cyclic type parameter bound is prohibited"
    end
  end
end
