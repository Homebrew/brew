# typed: strict
# frozen_string_literal: true

require "rspec/expectations"

module Tapioca
  module Compilers
    class RspecDynamicMatchers < Tapioca::Dsl::Compiler
      extend T::Generic

      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants
        [::RSpec::Matchers]
      end

      sig { override.void }
      def decorate
        used_matchers = T.let(Set.new, T::Set[String])
        Dir[File.join(__dir__, "../../../test/**/*_spec.rb")].each do |file|
          File.read(file).scan(/\b(?:be|have)_[a-z0-9_]+\b/) do |name|
            used_matchers.add(name)
          end
        end

        declared_dynamic_matchers = T.let(Set.new, T::Set[String])
        Dir[File.join(__dir__, "../../../test/**/*.rb")].select { |file| File.file?(file) }.each do |file|
          content = File.read(file)

          content.scan(/\b(?:RSpec::Matchers\.)?define\s+:([a-z][a-z0-9_]*[!?]?)/) do |captures|
            declared_dynamic_matchers.add(captures.first)
          end
          content.scan(/\b(?:RSpec::Matchers\.)?define_negated_matcher\s+:([a-z][a-z0-9_]*[!?]?)/) do |captures|
            declared_dynamic_matchers.add(captures.first)
          end
          content.scan(/\b(?:RSpec::Matchers\.)?alias_matcher\s+:([a-z][a-z0-9_]*[!?]?)/) do |captures|
            declared_dynamic_matchers.add(captures.first)
          end
          content.scan(/\bmatcher\s+:([a-z][a-z0-9_]*[!?]?)/) do |captures|
            declared_dynamic_matchers.add(captures.first)
          end
        end

        known_rspec_matchers = T.let(Set.new, T::Set[String])
        Dir[File.join(__dir__, "../../rbi/gems/rspec-expectations@*.rbi")].each do |file|
          File.read(file).scan(/^\s*def\s+([a-z][a-z0-9_]*[!?]?)/) do |captures|
            known_rspec_matchers.add(captures.first)
          end
        end

        root.create_path(constant) do |mod|
          (used_matchers + declared_dynamic_matchers - known_rspec_matchers).to_a.sort.each do |name|
            mod.create_method(
              name,
              parameters: [
                create_rest_param("args", type: "T.untyped"),
                create_block_param("block", type: "T.untyped"),
              ],
            )
          end
        end
      end
    end
  end
end
