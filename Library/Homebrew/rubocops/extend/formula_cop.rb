# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "rubocops/shared/helper_functions"

module RuboCop
  module Cop
    # Abstract base class for all formula cops.
    class FormulaCop < Base
      extend T::Helpers
      include RangeHelp
      include HelperFunctions

      abstract!
      exclude_from_registry

      attr_accessor :file_path

      @registry = Registry.global

      class FormulaNodes < T::Struct
        prop :node, RuboCop::AST::ClassNode
        prop :class_node, RuboCop::AST::ConstNode
        prop :parent_class_node, RuboCop::AST::ConstNode
        prop :body_node, RuboCop::AST::Node
      end

      # This method is called by RuboCop and is the main entry point.
      def on_class(node)
        @file_path = processed_source.file_path
        return unless file_path_allowed?
        return unless formula_class?(node)

        class_node, parent_class_node, @body = *node
        @formula_name = Pathname.new(@file_path).basename(".rb").to_s
        @tap_style_exceptions = nil
        audit_formula(FormulaNodes.new(node:, class_node:, parent_class_node:, body_node: @body))
      end

      sig { abstract.params(formula_nodes: FormulaNodes).void }
      def audit_formula(formula_nodes); end

      # Yields to block when there is a match.
      #
      # @param urls [Array] url/mirror method call nodes
      # @param regex [Regexp] pattern to match URLs
      def audit_urls(urls, regex)
        urls.each_with_index do |url_node, index|
          url_string_node = parameters(url_node).first
          url_string = string_content(url_string_node)
          match_object = regex_match_group(url_string_node, regex)
          next unless match_object

          offending_node(url_string_node.parent)
          yield match_object, url_string, index
        end
      end

      # Returns if the formula depends on dependency_name.
      #
      # @param dependency_name dependency's name
      def depends_on?(dependency_name, *types)
        return false if @body.nil?

        types = [:any] if types.empty?
        dependency_nodes = find_every_method_call_by_name(@body, :depends_on)
        idx = dependency_nodes.index do |n|
          types.any? { |type| depends_on_name_type?(n, dependency_name, type) }
        end
        return false if idx.nil?

        @offensive_node = dependency_nodes[idx]

        true
      end

      # Returns true if given dependency name and dependency type exist in given dependency method call node.
      # TODO: Add case where key of hash is an array
      def depends_on_name_type?(node, name = nil, type = :required)
        name_match = !name # Match only by type when name is nil

        case type
        when :required
          type_match = required_dependency?(node)
          name_match ||= required_dependency_name?(node, name) if type_match
        when :build, :test, :optional, :recommended
          type_match = dependency_type_hash_match?(node, type)
          name_match ||= dependency_name_hash_match?(node, name) if type_match
        when :any
          type_match = true
          name_match ||= required_dependency_name?(node, name)
          name_match ||= dependency_name_hash_match?(node, name)
        else
          type_match = false
        end

        @offensive_node = node if type_match || name_match
        type_match && name_match
      end

      def_node_search :required_dependency?, <<~EOS
        (send nil? :depends_on ({str sym} _))
      EOS

      def_node_search :required_dependency_name?, <<~EOS
        (send nil? :depends_on ({str sym} %1))
      EOS

      def_node_search :dependency_type_hash_match?, <<~EOS
        (hash (pair ({str sym} _) ({str sym} %1)))
      EOS

      def_node_search :dependency_name_hash_match?, <<~EOS
        (hash (pair ({str sym} %1) (...)))
      EOS

      # Return all the caveats' string nodes in an array.
      def caveats_strings
        return [] if @body.nil?

        find_strings(find_method_def(@body, :caveats))
      end

      # Returns the sha256 str node given a sha256 call node.
      def get_checksum_node(call)
        return if parameters(call).empty? || parameters(call).nil?

        if parameters(call).first.str_type?
          parameters(call).first
        # sha256 is passed as a key-value pair in bottle blocks
        elsif parameters(call).first.hash_type?
          if parameters(call).first.keys.first.value == :cellar
            # sha256 :cellar :any, :tag "hexdigest"
            parameters(call).first.values.last
          elsif parameters(call).first.keys.first.is_a?(RuboCop::AST::SymbolNode)
            # sha256 :tag "hexdigest"
            parameters(call).first.values.first
          else
            # Legacy bottle block syntax
            # sha256 "hexdigest" => :tag
            parameters(call).first.keys.first
          end
        end
      end

      # Yields to a block with comment text as parameter.
      def audit_comments
        processed_source.comments.each do |comment_node|
          @offensive_node = comment_node
          yield comment_node.text
        end
      end

      # Returns true if the formula is versioned.
      def versioned_formula?
        @formula_name.include?("@")
      end

      # Returns the formula tap.
      def formula_tap
        return unless (match_obj = @file_path.match(%r{/(homebrew-\w+)/}))

        match_obj[1]
      end

      # Returns the style exceptions directory from the file path.
      def style_exceptions_dir
        file_directory = File.dirname(@file_path)

        # if we're in a sharded subdirectory, look below that.
        directory_name = File.basename(file_directory)
        formula_directory = if directory_name.length == 1 || directory_name == "lib"
          File.dirname(file_directory)
        else
          file_directory
        end

        # if we're in a Formula or HomebrewFormula subdirectory, look below that.
        formula_directory_names = ["Formula", "HomebrewFormula"].freeze
        directory_name = File.basename(formula_directory)
        tap_root_directory = if formula_directory_names.include?(directory_name)
          File.dirname(formula_directory)
        else
          formula_directory
        end

        "#{tap_root_directory}/style_exceptions"
      end

      # Returns whether the given formula exists in the given style exception list.
      # Defaults to the current formula being checked.
      def tap_style_exception?(list, formula = nil)
        if @tap_style_exceptions.nil? && !formula_tap.nil?
          @tap_style_exceptions = {}

          Pathname.glob("#{style_exceptions_dir}/*.json").each do |exception_file|
            list_name = exception_file.basename.to_s.chomp(".json").to_sym
            list_contents = begin
              JSON.parse exception_file.read
            rescue JSON::ParserError
              nil
            end
            next if list_contents.nil? || list_contents.count.zero?

            @tap_style_exceptions[list_name] = list_contents
          end
        end

        return false if @tap_style_exceptions.nil? || @tap_style_exceptions.count.zero?
        return false unless @tap_style_exceptions.key? list

        @tap_style_exceptions[list].include?(formula || @formula_name)
      end

      private

      def formula_class?(node)
        _, class_node, = *node
        class_names = %w[
          Formula
          GithubGistFormula
          ScriptFileFormula
          AmazonWebServicesFormula
        ]

        class_node && class_names.include?(string_content(class_node))
      end

      def file_path_allowed?
        return true if @file_path.nil? # file_path is nil when source is directly passed to the cop, e.g. in specs

        !@file_path.include?("/Library/Homebrew/test/")
      end

      def on_system_methods
        @on_system_methods ||= [:intel, :arm, :macos, :linux, :system, *MacOSVersion::SYMBOLS.keys].map do |m|
          :"on_#{m}"
        end
      end
    end
  end
end
