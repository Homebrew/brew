# typed: strict
# frozen_string_literal: true

require "method_source"
require "rubocop"
require_relative "../../../rubocops"

module Tapioca
  module Compilers
    class RuboCop < Tapioca::Dsl::Compiler
      # This should be a module whose singleton class contains RuboCop::AST::NodePattern::Macros,
      #   but I don't know how to express that in Sorbet.
      ConstantType = type_member { { fixed: Module } }
      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants
        all_modules.select do |klass|
          next unless klass.singleton_class < ::RuboCop::AST::NodePattern::Macros

          path = T.must(Object.const_source_location(klass.to_s)).fetch(0).to_s
          # exclude vendored code, to avoid contradicting their RBI files
          !path.include?("/vendor/bundle/ruby/") &&
            # exclude source code that already has an RBI file
            !File.exist?("#{path}i") &&
            # exclude source code that doesn't use the DSLs
            File.readlines(path).any?(/def_node_/)
        end
      end

      sig { override.void }
      def decorate
        root.create_path(constant) do |klass|
          constant.instance_methods(false).each do |method_name|
            source = constant.instance_method(method_name).source.lstrip
            # For more info on these DSLs:
            #   https://www.rubydoc.info/gems/rubocop-ast/RuboCop/AST/NodePattern/Macros
            #   https://github.com/rubocop/rubocop-ast/blob/master/lib/rubocop/ast/node_pattern.rb
            #   https://github.com/rubocop/rubocop-ast/blob/master/lib/rubocop/ast/node_pattern/method_definer.rb
            # The type signatures below could maybe be stronger, but I only wanted to avoid errors:
            case source
            when /\Adef_node_matcher/
              # https://github.com/Shopify/tapioca/blob/3341a9b/lib/tapioca/rbi_ext/model.rb#L89
              klass.create_method(
                method_name.to_s,
                parameters:  [
                  create_param("node", type: "RuboCop::AST::Node"),
                  create_kw_rest_param("kwargs", type: "T.untyped"),
                  create_block_param("block", type: "T.untyped"),
                ],
                return_type: "T.untyped",
              )
            when /\Adef_node_search/
              klass.create_method(
                method_name.to_s,
                parameters:  [
                  create_param("node", type: "RuboCop::AST::Node"),
                  create_rest_param("pattern", type: "T.any(String, Symbol)"),
                  create_kw_rest_param("kwargs", type: "T.untyped"),
                  create_block_param("block", type: "T.untyped"),
                ],
                return_type: method_name.to_s.end_with?("?") ? "T::Boolean" : "T.untyped",
              )
            end
          end
        end
      end
    end
  end
end
