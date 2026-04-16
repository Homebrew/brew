# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"
require "rubocops/shared/api_annotation_helper"

module RuboCop
  module Cop
    module FormulaAudit
      # Ensures that formulae in official taps (homebrew-core, homebrew-cask)
      # only use methods that are part of the public API (`@api public`) and
      # do not call methods marked as `@api private` or `@api internal`.
      #
      # The lists of internal/private methods are derived dynamically from
      # `@api` annotations in the source files rather than hardcoded, so
      # they stay in sync automatically.
      #
      # ### Example
      #
      # ```ruby
      # # bad - `tap` is @api internal
      # class Foo < Formula
      #   def install
      #     puts tap
      #   end
      # end
      #
      # # good - `bin` is @api public
      # class Foo < Formula
      #   def install
      #     bin.install "foo"
      #   end
      # end
      # ```
      class NonPublicApiUsage < FormulaCop
        INTERNAL_MSG = "Do not use `%<method>s` in official tap formulae; it is an internal API (`@api internal`)."
        PRIVATE_MSG = "Do not use `%<method>s` in official tap formulae; it is a private API (`@api private`)."

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if ApiAnnotationHelper::OFFICIAL_TAPS.none?(formula_tap)
          return if (body_node = formula_nodes.body_node).nil?

          check_method_calls(body_node, internal_methods, INTERNAL_MSG)
          check_method_calls(body_node, private_methods, PRIVATE_MSG)
        end

        private

        sig { returns(T::Set[String]) }
        def internal_methods
          @internal_methods ||= T.let(
            load_methods_for_level("internal"),
            T.nilable(T::Set[String]),
          )
        end

        sig { returns(T::Set[String]) }
        def private_methods
          @private_methods ||= T.let(
            load_methods_for_level("private"),
            T.nilable(T::Set[String]),
          )
        end

        sig { params(level: String).returns(T::Set[String]) }
        def load_methods_for_level(level)
          methods = T.let(Set.new, T::Set[String])
          ApiAnnotationHelper::API_SOURCE_FILES.each do |source_file|
            methods.merge(ApiAnnotationHelper.methods_with_api_level(
                            File.join(ApiAnnotationHelper.homebrew_dir, source_file), level
                          ))
          end
          methods
        end

        sig {
          params(
            body_node: RuboCop::AST::Node,
            methods:   T::Set[String],
            msg:       String,
          ).void
        }
        def check_method_calls(body_node, methods, msg)
          methods.each do |method_name|
            find_every_method_call_by_name(body_node, method_name.to_sym).each do |node|
              # Only flag implicit receiver calls (i.e. `tap` not `foo.tap`)
              # to reduce false positives from local variables or other objects.
              next if node.receiver && !node.receiver.self_type?

              @offensive_node = node
              problem format(msg, method: method_name)
            end
          end
        end
      end
    end
  end
end
