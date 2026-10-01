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
      # validated by this cop.
      class PublicApiCookbook < Base
        MSG = "Method `%<method>s` is referenced in the %<cookbook>s but is not annotated with `@api public`."
        MISSING_FORMULA_LIST_MSG = "Formula Cookbook references methods missing from " \
                                   "`FORMULA_COOKBOOK_METHODS`: %<methods>s."
        MISSING_CASK_LIST_MSG = "Method `%<method>s` is annotated with `@api public` in `%<file>s` but is " \
                                "missing from `CASK_COOKBOOK_METHODS`."
        MISSING_SERVICE_LIST_MSG = "Method `%<method>s` is annotated with `@api public` in `service.rb` but is " \
                                   "missing from the Formula Cookbook's \"Service block methods\" table."
        MISMATCHED_SERVICE_LIST_MSG = "`SERVICE_COOKBOOK_METHODS` is out of sync with the Formula Cookbook's " \
                                      "\"Service block methods\" table: %<diff>s."

        sig { void }
        def on_new_investigation
          super

          file_path = processed_source.file_path
          return if file_path.nil?

          relative_path = file_path.sub(%r{.*/Library/Homebrew/}, "")

          if relative_path == "rubocops/shared/api_annotation_helper.rb"
            missing_formula = (HOMEBREW_LIBRARY_PATH.parent.parent/"docs/Formula-Cookbook.md").read
                              .scan(
                                %r{/rubydoc/\w+(?:/\w+)*\.html#(\w+[!?]?)-(?:class|instance)_method},
                              )
                              .flatten -
                              ApiAnnotationHelper::FORMULA_COOKBOOK_METHODS.keys
            missing_formula.sort!

            if missing_formula.any?
              add_offense(
                processed_source.ast&.each_descendant(:casgn)&.find do |node|
                  node.const_name == "FORMULA_COOKBOOK_METHODS"
                end || processed_source.ast || processed_source.buffer.source_range,
                message: format(
                  MISSING_FORMULA_LIST_MSG,
                  methods: missing_formula.map { |method| "`#{method}`" }.join(", "),
                ),
              )
            end

            check_service_cookbook_list

            return
          end

          api_public_targets = build_api_public_targets

          check_cookbook_methods(ApiAnnotationHelper::FORMULA_COOKBOOK_METHODS,
                                 "Formula Cookbook", relative_path, api_public_targets)
          check_cookbook_methods(ApiAnnotationHelper::CASK_COOKBOOK_METHODS,
                                 "Cask Cookbook", relative_path, api_public_targets)
          check_service_methods(relative_path, api_public_targets)

          return unless %w[cask/dsl.rb cask/cask.rb cask/dsl/version.rb].include?(relative_path)

          cookbook_methods = ApiAnnotationHelper::CASK_COOKBOOK_METHODS.keys.to_set
          lines = processed_source.lines

          processed_source.comments.each do |comment|
            next unless ["# @api public", "@api public"].include?(comment.text.strip)

            (1..5).each do |offset|
              target_line = lines[comment.loc.line - 1 + offset]&.strip
              break if target_line.blank?

              match = target_line.match(/\A(?:def\s+(?:self\.)?|attr_reader\s+:|attr_accessor\s+:)(\w+[!?]?)/) ||
                      target_line.match(/\Adelegate\s+(\w+[!?]?):/)
              next if match.nil?

              method_name = match[1].to_s
              break if cookbook_methods.include?(method_name)

              add_offense(comment, message: format(MISSING_CASK_LIST_MSG, method: method_name, file: relative_path))
              break
            end
          end
        end

        private

        # Build a set of line numbers for definitions that are directly
        # preceded by an `@api public` annotation in their doc block.
        # Walks forward from each `@api public` comment to find the next
        # def/attr_reader/delegate, matching only the immediately following
        # definition; not one 20 lines away.
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

        # Ensure `SERVICE_COOKBOOK_METHODS` stays a 1:1 mirror of the cookbook's
        # "Service block methods" table.
        sig { void }
        def check_service_cookbook_list
          table = parse_service_block_table
          list = ApiAnnotationHelper::SERVICE_COOKBOOK_METHODS
          return if table == list

          diff = []
          if (missing_from_list = (table - list).to_a.sort).any?
            diff << "missing from the list: #{missing_from_list.map { |m| "`#{m}`" }.join(", ")}"
          end
          if (missing_from_table = (list - table).to_a.sort).any?
            diff << "not in the cookbook table: #{missing_from_table.map { |m| "`#{m}`" }.join(", ")}"
          end

          node = processed_source.ast&.each_descendant(:casgn)&.find do |casgn|
            casgn.const_name == "SERVICE_COOKBOOK_METHODS"
          end
          add_offense(node || processed_source.ast || processed_source.buffer.source_range,
                      message: format(MISMATCHED_SERVICE_LIST_MSG, diff: diff.join("; ")))
        end

        # Cross-check `service.rb`'s `@api public` annotations against the
        # "Service block methods" table: every documented method must be
        # `@api public` and every `@api public` method must be documented.
        sig { params(relative_path: String, api_public_targets: T::Set[Integer]).void }
        def check_service_methods(relative_path, api_public_targets)
          return if relative_path != "service.rb"

          documented = ApiAnnotationHelper::SERVICE_COOKBOOK_METHODS
          processed_source.ast&.each_descendant(:def, :defs) do |node|
            method_name = node.method_name.to_s
            annotated = api_public_targets.include?(node.loc.line)

            if documented.include?(method_name) && !annotated
              add_offense(node, message: format(MSG, method: method_name, cookbook: "Formula Cookbook"))
            elsif annotated && !documented.include?(method_name)
              add_offense(node, message: format(MISSING_SERVICE_LIST_MSG, method: method_name))
            end
          end
        end

        # Method names in the first (backticked) column of the "Service block
        # methods" table in docs/Formula-Cookbook.md.
        sig { returns(T::Set[String]) }
        def parse_service_block_table
          path = HOMEBREW_LIBRARY_PATH.parent.parent/"docs/Formula-Cookbook.md"
          return Set.new unless path.exist?

          lines = path.readlines
          start = lines.index { |line| line.start_with?("#### Service block methods") }
          return Set.new if start.nil?

          rest = lines[(start + 1)..] || []
          finish = rest.index { |line| line.start_with?("#") } || rest.length
          rest[0, finish].filter_map { |line| line[/\A\|\s*`([^`]+)`/, 1] }.to_set
        end
      end
    end
  end
end
