# typed: strict
# frozen_string_literal: true

require "rubocops/shared/api_annotation_helper"

module RuboCop
  module Cop
    module Homebrew
      # Ensures that methods and DSL calls documented in the Formula Cookbook
      # or Cask Cookbook are annotated with `@api public` in their source
      # definitions.
      #
      # Both cookbook method lists live in {ApiAnnotationHelper} and are
      # validated by `.github/check_cookbook_method_lists.rb` in CI.
      class PublicApiCookbook < Base
        MSG = "Method `%<method>s` is referenced in the %<cookbook>s but is not annotated with `@api public`."

        sig { void }
        def on_new_investigation
          super

          file_path = processed_source.file_path
          return if file_path.nil?

          relative_path = file_path.sub(%r{.*/Library/Homebrew/}, "")
          api_public_targets = build_api_public_targets

          check_cookbook_methods(ApiAnnotationHelper::FORMULA_COOKBOOK_METHODS,
                                 "Formula Cookbook", relative_path, api_public_targets)
          check_cookbook_methods(ApiAnnotationHelper::CASK_COOKBOOK_METHODS,
                                 "Cask Cookbook", relative_path, api_public_targets)
        end

        private

        # Build a set of line numbers for definitions that are directly
        # preceded by an `@api public` annotation in their doc block.
        # Walks forward from each `@api public` comment to find the next
        # def/attr_reader/delegate, matching only the immediately following
        # definition — not one 20 lines away.
        sig { returns(T::Set[Integer]) }
        def build_api_public_targets
          targets = T.let(Set.new, T::Set[Integer])
          lines = processed_source.lines

          processed_source.comments.each do |comment|
            text = comment.text.strip
            next if text != "# @api public" && text != "@api public"

            # Scan forward from the annotation to find the definition it applies to.
            # Skip blank lines, comments, and sig blocks (including multi-line).
            line_idx = comment.loc.line # 1-based; lines array is 0-based
            in_sig = T.let(false, T::Boolean)
            (1..15).each do |offset|
              target_line = lines[line_idx - 1 + offset]&.strip
              break if target_line.nil?
              next if target_line.empty? || target_line.start_with?("#")

              if target_line.match?(/(?:\A|\.|\})sig[\s({]/)
                in_sig = !target_line.include?("}")
                next
              end

              if in_sig
                in_sig = !target_line.include?("}")
                next
              end

              targets.add(line_idx + offset)
              break
            end
          end

          targets
        end

        sig {
          params(
            cookbook_methods:   T::Hash[String, String],
            cookbook_name:      String,
            relative_path:      String,
            api_public_targets: T::Set[Integer],
          ).void
        }
        def check_cookbook_methods(cookbook_methods, cookbook_name, relative_path, api_public_targets)
          relevant_methods = cookbook_methods.select { |_, file| file == relative_path }
          return if relevant_methods.empty?

          method_names = relevant_methods.keys.to_set

          processed_source.ast&.each_descendant(:def, :defs, :send) do |node|
            method_name = case node.type
            when :def, :defs
              node.method_name.to_s
            when :send
              next unless [:attr_reader, :attr_accessor].include?(node.method_name)

              node.arguments.each do |arg|
                next unless arg.sym_type?

                attr_name = arg.value.to_s
                next unless method_names.include?(attr_name)
                next if api_public_targets.include?(node.loc.line)

                add_offense(node,
                            message: format(MSG, method: attr_name, cookbook: cookbook_name))
              end
              next
            end

            next if method_name.nil?
            next unless method_names.include?(method_name)
            next if api_public_targets.include?(node.loc.line)

            add_offense(node, message: format(MSG, method: method_name, cookbook: cookbook_name))
          end
        end
      end
    end
  end
end
