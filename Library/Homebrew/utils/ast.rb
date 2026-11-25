# typed: strict
# frozen_string_literal: true

require "ast_constants"
require "on_system"
require "rubocop-ast"
require "rubocops/cask/constants/stanza"
require "url"

module Utils
  # Helper functions for editing Ruby files.
  module AST
    Node = RuboCop::AST::Node
    SendNode = RuboCop::AST::SendNode
    BlockNode = RuboCop::AST::BlockNode
    DefNode = RuboCop::AST::DefNode
    ProcessedSource = RuboCop::AST::ProcessedSource
    TreeRewriter = Parser::Source::TreeRewriter

    module_function

    sig { params(body_node: T.nilable(Node)).returns(T::Array[Node]) }
    def body_children(body_node)
      if body_node.blank?
        []
      elsif body_node.begin_type?
        body_node.children.compact
      else
        [body_node]
      end
    end

    sig { params(name: Symbol, value: T.any(Numeric, String, Symbol), indent: T.nilable(Integer)).returns(String) }
    def stanza_text(name, value, indent: nil)
      text = if value.is_a?(String)
        _, node = process_source(value)
        value if (node.is_a?(SendNode) || node.is_a?(BlockNode)) && node.method_name == name
      end
      text ||= "#{name} #{value.inspect}"
      text = text.gsub(/^(?!$)/, " " * indent) if indent && !text.match?(/\A\n* +/)
      text
    end

    sig { params(value: T.any(Numeric, String, Symbol)).returns(String) }
    def ruby_literal(value)
      value.inspect
    end

    sig { params(node: Node).returns(T.untyped) }
    def literal_value(node)
      return node.str_content if node.str_type?
      return node.value if node.is_a?(RuboCop::AST::BasicLiteralNode) && (node.sym_type? || node.numeric_type?)

      nil
    end

    sig { params(source: String).returns([ProcessedSource, Node]) }
    def process_source(source)
      ruby_version = Version.new(HOMEBREW_REQUIRED_RUBY_VERSION).major_minor.to_f
      processed_source = ProcessedSource.new(source, ruby_version)
      root_node = processed_source.ast
      [processed_source, root_node]
    end

    sig {
      params(
        component_name: Symbol,
        component_type: Symbol,
        target_name:    Symbol,
        target_type:    T.nilable(Symbol),
      ).returns(T::Boolean)
    }
    def component_match?(component_name:, component_type:, target_name:, target_type: nil)
      component_name == target_name && (target_type.nil? || component_type == target_type)
    end

    sig { params(node: Node, name: Symbol, type: T.nilable(Symbol)).returns(T::Boolean) }
    def call_node_match?(node, name:, type: nil)
      node_type = case node
      when SendNode then :method_call
      when BlockNode then :block_call
      else return false
      end

      component_match?(component_name: node.method_name,
                       component_type: node_type,
                       target_name:    name,
                       target_type:    type)
    end

    # Helper class for editing formulae.
    class FormulaAST
      extend Forwardable
      include AST

      patch_platform_blocks = [*OnSystem::ARCH_OPTIONS, *OnSystem::BASE_OS_OPTIONS, *MacOSVersion::SYMBOLS.keys,
                               :system].map do |name|
        :"on_#{name}"
      end
      PATCH_PLATFORM_BLOCKS = T.let(patch_platform_blocks.freeze, T::Array[Symbol])
      BUMP_URL_ORIGIN = %r{\A(?i:https?|ftp)://[a-zA-Z0-9.:-]+(?=/|\z)}
      PYPI_RESOURCE = %r{\Aresource[ ]"[a-zA-Z0-9._+-]+"[ ]do
                           \n[ ]+url[ ]"https://files\.pythonhosted\.org/[-a-zA-Z0-9_./%+]+"
                           \n[ ]+sha256[ ]"[a-f0-9]{64}"\n[ ]+end\z}x

      delegate process: :tree_rewriter

      # Top-level nodes in the formula body.
      sig { returns(T::Array[Node]) }
      attr_reader :children

      sig { params(formula_contents: String).void }
      def initialize(formula_contents)
        @formula_contents = formula_contents
        processed_source, root_node = process_source(formula_contents)

        class_node = root_node if root_node.class_type?
        if root_node.begin_type?
          nodes = root_node.children.select(&:class_type?)
          class_node = if nodes.count > 1
            nodes.find { |n| n.parent_class&.const_name == "Formula" }
          else
            nodes.first
          end
        end

        raise "Could not find formula class!" if class_node.nil?

        children = body_children(class_node.body)
        raise "Formula class is empty!" if children.empty?

        @processed_source = T.let(processed_source, ProcessedSource)
        @children = T.let(children, T::Array[Node])
        @tree_rewriter = T.let(TreeRewriter.new(processed_source.buffer), TreeRewriter)
      end

      # Compare a prepared formula with the release edits allowed in its checkout.
      sig { params(original: String, proposed: String, version: T.nilable(String)).returns(T::Boolean) }
      def self.valid_bump?(original, proposed, version: nil)
        checkout = new(original)
        proposal = new(proposed)
        if version
          current = checkout.stable_version
          return false if !current || proposal.stable_version != version
          return false if Version.new(version) <= Version.new(current)
        end

        return true if checkout.bump_template(proposal) == proposal.bump_template(proposal)

        checkout.matches_patch_removals?(proposal)
      end

      sig { returns(T::Hash[Symbol, T.nilable(SendNode)]) }
      def stable_declarations
        nodes = children.dup
        declarations = []
        independent_scopes = [:resource, :head, :patch, :livecheck, :bottle, :service, :test]
        while (node = nodes.pop)
          next if node.class_type? || node.module_type? || node.def_type? || node.defs_type?
          next if node.is_a?(BlockNode) && !node.send_node.receiver && independent_scopes.include?(node.method_name)

          if node.is_a?(SendNode) && [:url, :version].include?(node.method_name) && node.arguments.present?
            declarations << node
          end
          nodes.concat(node.child_nodes)
        end

        declarations.group_by(&:method_name).transform_values do |calls|
          call = calls.fetch(0)
          next if !calls.one? || call.receiver
          next unless call.each_ancestor.all? do |scope|
            scope.class_type? || scope.begin_type? ||
            (scope.is_a?(BlockNode) && scope.method?(:stable) && scope.send_node.receiver.nil?)
          end

          call
        end
      end
      private :stable_declarations

      # Read the stable version without evaluating the formula.
      sig { returns(T.nilable(String)) }
      def stable_version
        declarations = stable_declarations
        unless declarations.key?(:version)
          return stable_source(declarations[:url], keys: [:tag])&.version&.to_s.presence
        end

        call = declarations[:version]
        return unless call

        call.first_argument&.str_content.presence if call.arguments.one?
      end

      # Extract literal source details used to identify the proposed release.
      sig { params(call: T.nilable(SendNode), keys: T::Array[Symbol]).returns(T.nilable(URL)) }
      def stable_source(call = stable_declarations[:url], keys: [:tag, :revision])
        value = call&.first_argument&.str_content
        return if !call || value.blank?

        specs = {}
        if (options = call.arguments[1])
          return if call.arguments.length != 2 || !options.is_a?(RuboCop::AST::HashNode)

          return unless options.children.all? { |pair| pair.pair_type? && pair.key.sym_type? }

          keys.each do |key|
            pair = options.pairs.rfind { |entry| entry.key.value == key }
            next unless pair
            return nil unless pair.value.str_type?

            specs[key] = pair.value.str_content
          end
        end
        URL.new(value, specs)
      end

      # Keep executable source intact while comparing release declarations.
      sig { params(proposal: FormulaAST).returns(String) }
      def bump_template(proposal)
        if (mirrors = stable_mirror_origins).present?
          retained = proposal.retained_mirror_origins
          mirrors.each do |node, origin|
            if retained.first == origin
              retained.shift
            else
              remove_stanza_node(node)
            end
          end
        end

        nodes = children.dup
        while (node = nodes.shift)
          case node
          when BlockNode
            next if node.send_node.receiver || node.arguments.children.present?

            if [:stable, *PATCH_PLATFORM_BLOCKS].include?(node.method_name)
              nodes.concat(body_children(node.body))
              next
            end
            next unless node.method?(:resource)

            statements = body_children(node.body)
            version = statements.grep(SendNode).find do |call|
              call.method?(:version) && call.receiver.nil? && call.arguments.one? && call.first_argument&.str_type?
            end
            # PyPI regenerates the resource with just its URL and checksum.
            source = node.source
            source = source.sub(/^ +#{Regexp.escape(version.source)}\n/, "") if version
            if PYPI_RESOURCE.match?(source)
              remove_stanza_node(node)
            else
              nodes.concat(statements)
            end
          when SendNode
            next if node.receiver

            value = node.first_argument
            if node.arguments.one? && ((node.method?(:revision) && value&.int_type?) ||
               ([:sha256, :version].include?(node.method_name) && value&.str_type?))
              remove_stanza_node(node)
            elsif [:url, :mirror].include?(node.method_name) && value&.str_type?
              origin = value.str_content[BUMP_URL_ORIGIN]
              tree_rewriter.replace(value.source_range, origin.inspect) if origin
              node.arguments.grep(RuboCop::AST::HashNode).each do |options|
                options.pairs.each do |pair|
                  next if !pair.key.sym_type? || [:tag, :revision].exclude?(pair.key.value) || !pair.value.str_type?

                  tree_rewriter.replace(pair.value.source_range, '""')
                end
              end
            end
          end
        end
        process
      end

      # Compare patch edits at their original positions in the two release templates.
      sig { params(proposal: FormulaAST).returns(T::Boolean) }
      def matches_patch_removals?(proposal)
        scopes = patches_by_scope
        return false if scopes.empty?

        candidates_by_scope = proposal.patches_by_scope
        removals = {}.compare_by_identity
        scopes.each do |scope, patches|
          candidates = candidates_by_scope.fetch(scope, []).map(&:source)
          unmatched = patches.reject do |patch|
            index = candidates.index(patch.source)
            candidates.delete_at(index) if index
          end
          unmatched.each do |patch|
            candidate = candidates.first
            if candidate && (branches = prepared_patch_branches(patch, candidate))
              candidates.shift
              removals[patch] = branches
            else
              removals[patch] = patches_for_removal(patch) { |_urls, branch| branch.equal?(patch) }
            end
          end
        end
        removed_urls = Set.new
        remove_patches do |patch|
          selected = removals.fetch(patch, [])
          next [] if selected.empty?

          patches_for_removal(patch) do |urls, branch|
            next false unless selected.any? { |node| node.equal?(branch) }

            removed_urls.merge(urls)
            true
          end
        end
        return false if removed_urls.empty? || process != proposal.process

        source = proposal.stable_source
        return false unless source

        require "utils/github/patch_inclusion"

        inclusion = GitHub::PatchInclusion.new
        removed_urls.all? do |url|
          inclusion.removal_reason(url, source_url: source.to_s, tag: source.specs[:tag],
                                        revision: source.specs[:revision]).present?
        end
      end

      sig { returns(T.nilable(Node)) }
      def bottle_block
        stanza(:bottle, type: :block_call)
      end

      sig { params(name: Symbol, type: T.nilable(Symbol)).returns(T.nilable(Node)) }
      def stanza(name, type: nil)
        stanzas(name, type:).first
      end

      sig { params(name: Symbol, type: T.nilable(Symbol)).returns(T::Array[Node]) }
      def stanzas(name, type: nil)
        matching_stanzas(children, name, type:)
      end

      sig { params(name: String).returns(BlockNode) }
      def resource(name)
        possible_resource_stanzas = if stanza(:stable, type: :block_call).present?
          # Needed resource block may be either in `stable` or in formula body, hence appending
          # `children` nodes
          stable_children + children
        else
          children
        end
        resource = matching_stanzas(possible_resource_stanzas, :resource, type: :block_call).find do |resource_node|
          T.cast(resource_node, BlockNode).send_node.first_argument&.str_content == name
        end
        raise "Could not find resource '#{name}' block!" if resource.blank?

        T.cast(resource, BlockNode)
      end

      sig { params(name: Symbol, value: T.any(Numeric, String, Symbol)).void }
      def replace_stable_stanza_value(name, value)
        replace_stanza_value(stable_stanza(name), value)
      end

      sig { params(name: Symbol, key: Symbol, value: T.any(Numeric, String, Symbol)).void }
      def replace_stable_stanza_hash_value(name, key, value)
        replace_stanza_hash_value(stable_stanza(name), key, value)
      end

      sig { params(name: Symbol).returns(T::Boolean) }
      def stable_stanza?(name)
        matching_stanzas(stable_children, name).present?
      end

      sig { params(name: Symbol).void }
      def remove_stable_stanza(name)
        remove_stanza_node(stable_stanza(name))
      end

      sig { params(name: Symbol).void }
      def remove_stable_stanzas(name)
        stanza_nodes = matching_stanzas(stable_children, name)
        raise "Could not find '#{name}' stanza!" if stanza_nodes.empty?

        stanza_nodes.each { |stanza_node| remove_stanza_node(stanza_node) }
      end

      sig {
        params(
          after_name:  Symbol,
          new_stanzas: T::Array[[Symbol, T.any(Numeric, String, Symbol)]],
        ).void
      }
      def add_stable_stanzas_after(after_name, new_stanzas)
        add_stanzas_after(after_name, new_stanzas, parent: stanza(:stable, type: :block_call))
      end

      sig {
        params(
          resource_name: String,
          name:          Symbol,
          value:         T.any(Numeric, String, Symbol),
          old_value:     T.nilable(T.any(Numeric, String, Symbol)),
        ).void
      }
      def replace_resource_stanza_value(resource_name, name, value, old_value: nil)
        replace_stanza_value(resource_stanza(resource_name, name, old_value:), value)
      end

      sig {
        params(
          resource_name: String,
          name:          Symbol,
          key:           Symbol,
          value:         T.any(Numeric, String, Symbol),
        ).void
      }
      def replace_resource_stanza_hash_value(resource_name, name, key, value)
        replace_stanza_hash_value(resource_stanza(resource_name, name), key, value)
      end

      sig { params(resource_name: String, name: Symbol).returns(T::Boolean) }
      def resource_stanza?(resource_name, name)
        matching_stanzas(body_children(resource(resource_name).body), name).present?
      end

      sig {
        params(
          after_name:  Symbol,
          new_stanzas: T::Array[[Symbol, T.any(Numeric, String, Symbol)]],
          parent:      T.nilable(Node),
        ).void
      }
      def add_stanzas_after(after_name, new_stanzas, parent: nil)
        return if new_stanzas.empty?

        preceding_component = if parent
          matching_stanzas(body_children(T.cast(parent, BlockNode).body), after_name).last
        else
          stanza(after_name)
        end
        raise "Could not find '#{after_name}' stanza!" if preceding_component.blank?

        preceding_expr = preceding_component.location.expression
        processed_source.comments.each do |comment|
          comment_expr = comment.location.expression
          distance = comment_expr.first_line - preceding_expr.last_line
          case distance
          when 0
            if comment_expr.last_line > preceding_expr.last_line ||
               comment_expr.end_pos > preceding_expr.end_pos
              preceding_expr = comment_expr
            end
          when 1
            preceding_expr = comment_expr
          end
        end
        text = new_stanzas.map do |stanza_name, value|
          stanza = stanza_text(stanza_name, value, indent: preceding_component.source_range.column)
          "\n#{stanza}"
        end.join
        tree_rewriter.insert_after(preceding_expr, text)
      end

      sig {
        params(
          resource_section:   String,
          replace_existing:   T::Boolean,
          preserve_livecheck: T::Boolean,
        ).returns(T.nilable(Symbol))
      }
      def replace_resource_stanzas(resource_section, replace_existing: true, preserve_livecheck: false)
        resource_section = resource_section.gsub(/^(?!$)/, "  ") unless resource_section.match?(/\A\n* +/)

        if replace_existing
          test_node = stanza(:test, type: :block_call)
          resource_nodes = stanzas(:resource, type: :block_call).filter_map do |node|
            node = T.cast(node, BlockNode)
            next if test_node.present? && node.source_range.begin_pos > test_node.source_range.begin_pos

            next if preserve_livecheck &&
                    matching_stanzas(body_children(node.body), :livecheck, type: :block_call).present?

            node
          end

          groups = T.let([], T::Array[T::Array[BlockNode]])
          resource_nodes.each do |resource_node|
            previous_group = groups.last
            if previous_group
              previous_end = whole_line_range(previous_group.fetch(-1).source_range).end_pos
              current_start = resource_node.source_range.begin_pos - resource_node.source_range.column
              contiguous = formula_contents[previous_end...current_start].to_s.lines.all? do |line|
                line.strip.empty? || line.strip.start_with?("# RESOURCE-ERROR:")
              end
            end

            if previous_group && contiguous
              previous_group << resource_node
            else
              groups << [resource_node]
            end
          end
          return :multiple_groups if groups.length > 1

          if (group = groups.first)
            # Include any `# RESOURCE-ERROR:` comments directly above the first resource.
            first_range = group.fetch(0).source_range
            loop do
              line_start = first_range.begin_pos - first_range.column
              previous_comments = processed_source.comments.select do |comment|
                comment.location.expression.end_pos <= line_start &&
                  comment.text.start_with?("# RESOURCE-ERROR:")
              end
              previous_comment = previous_comments.max_by { |comment| comment.location.expression.end_pos }
              break if previous_comment.blank?

              comment_range = previous_comment.location.expression
              break unless formula_contents[comment_range.end_pos...line_start].to_s.lines.all? do |line|
                line.strip.empty?
              end

              first_range = T.cast(first_range.with(begin_pos: comment_range.begin_pos), Parser::Source::Range)
            end
            last_range = whole_line_range(group.fetch(-1).source_range, include_following_blank_lines: true)
            group_range = first_range.with(
              begin_pos: first_range.begin_pos - first_range.column,
              end_pos:   last_range.end_pos,
            )
            tree_rewriter.replace(group_range, resource_section)
            return
          end
        end

        install_node = children.find { |child| child.def_type? && T.cast(child, DefNode).method_name == :install }
        install_node = T.cast(install_node, T.nilable(DefNode))
        raise "Could not find 'install' method!" if install_node.blank?

        tree_rewriter.insert_before(whole_line_range(install_node.source_range), resource_section)
        nil
      end

      sig { params(bottle_output: String).void }
      def replace_bottle_block(bottle_output)
        replace_stanza(:bottle, bottle_output.chomp, type: :block_call)
      end

      sig { params(bottle_output: String).void }
      def add_bottle_block(bottle_output)
        add_stanza(:bottle, "\n#{bottle_output.chomp}", type: :block_call)
      end

      sig { params(name: Symbol, type: T.nilable(Symbol)).void }
      def remove_stanza(name, type: nil)
        stanza_node = stanza(name, type:)
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        remove_stanza_node(stanza_node)
      end

      # Selects whole patches or independent platform branches containing only supported declarations.
      # The caller decides whether to remove a branch given all its patch URLs.
      sig {
        params(node: BlockNode, block: T.proc.params(urls: T::Array[String], branch: BlockNode).returns(T::Boolean))
          .returns(T::Array[BlockNode])
      }
      def patches_for_removal(node, &block)
        # Retain stable-only patches to avoid leaving a redundant `stable` block.
        return [] unless node.each_ancestor.all? do |parent|
          parent.class_type? || parent.begin_type? ||
          (parent.is_a?(BlockNode) && parent.send_node.receiver.nil? &&
           [:patch, *PATCH_PLATFORM_BLOCKS].include?(parent.method_name))
        end
        return [] unless node.arguments.empty?

        if node.method_name == :patch && (arguments = node.send_node.arguments).present?
          strip = literal_value(arguments.first)
          return [] if arguments.length != 1 || !strip.is_a?(Symbol) || !strip.to_s.match?(/\Ap\d+\z/)
        end

        children = body_children(node.body)
        calls = patch_scope_nodes(children)
        unsupported_calls = calls.reject do |call|
          case call
          when SendNode
            call.receiver.nil? && [:url, :sha256, :directory, :type, :resolves].include?(call.method_name)
          when BlockNode
            call.send_node.receiver.nil? && call.arguments.empty? && PATCH_PLATFORM_BLOCKS.include?(call.method_name)
          end
        end

        if unsupported_calls.empty?
          urls = calls.grep(SendNode).select { |call| call.method_name == :url }.map do |call|
            value = call.first_argument
            value.str_content if call.arguments.length == 1 && value&.str_type?
          end
          return [node] if urls.present? && urls.none?(&:nil?) && yield(urls.compact.uniq, node)
        end

        return [] if children.any? do |child|
          unsupported_calls.include?(child) || (child.is_a?(SendNode) && child.method_name == :url)
        end

        branches = children.grep(BlockNode)
        if branches.length > 1
          # Only split disjoint OS or architecture pairs.
          return [] unless branches.all? { |branch| branch.send_node.arguments.empty? }
          return [] unless [[:on_linux, :on_macos], [:on_arm, :on_intel]].include?(branches.map(&:method_name).sort)
        end

        branches.flat_map { |branch| patches_for_removal(branch, &block) }
      end

      # Enumerates source declarations in stable and platform scopes.
      sig { params(nodes: T::Array[Node]).returns(T::Array[Node]) }
      def patch_scope_nodes(nodes = children)
        nodes.flat_map do |node|
          if node.is_a?(BlockNode) && node.send_node.receiver.nil? &&
             [:stable, *PATCH_PLATFORM_BLOCKS].include?(node.method_name)
            [node, *patch_scope_nodes(body_children(node.body))]
          else
            [node]
          end
        end
      end

      # Yields patch blocks in all scopes; the caller returns patches or branches to remove.
      # Removes adjoining comments and platform wrappers emptied by patch removal.
      sig { params(block: T.proc.params(node: BlockNode).returns(T::Array[BlockNode])).void }
      def remove_patches(&block)
        nodes = children.flat_map { |node| node.each_node(:block).to_a }.grep(BlockNode)
        removals = nodes.flat_map do |node|
          next [] if node.method_name != :patch || node.send_node.receiver

          yield(node)
        end

        nodes.reverse_each do |node|
          next if node.send_node.receiver
          next unless PATCH_PLATFORM_BLOCKS.include?(node.method_name)
          next if node.body.nil?
          next unless body_children(node.body).all? { |child| removals.any? { |removal| removal.equal?(child) } }

          removals.reject! { |removal| node.source_range.contains?(removal.source_range) }
          removals << node
        end
        removals.each { |node| remove_stanza_node(node, remove_leading_comments: true) }
      end

      # Finds DSL calls regardless of their platform or enclosing scope.
      sig { params(name: Symbol).returns(T::Boolean) }
      def contains_call?(name)
        children.any? do |node|
          node.each_node(:send).any? do |call|
            call.method_name == name && call.receiver.nil?
          end
        end
      end

      sig { params(name: Symbol, replacement: T.any(Numeric, String, Symbol), type: T.nilable(Symbol)).void }
      def replace_stanza(name, replacement, type: nil)
        stanza_node = stanza(name, type:)
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        tree_rewriter.replace(stanza_node.source_range, stanza_text(name, replacement, indent: 2).lstrip)
      end

      sig { params(name: Symbol, value: T.any(Numeric, String, Symbol), type: T.nilable(Symbol)).void }
      def add_stanza(name, value, type: nil)
        preceding_component = if children.length > 1
          children.reduce do |previous_child, current_child|
            if formula_component_before_target?(current_child,
                                                target_name: name,
                                                target_type: type)
              next current_child
            else
              break previous_child
            end
          end
        else
          children.first
        end
        preceding_component = preceding_component.last_argument if preceding_component.is_a?(SendNode)

        preceding_expr = preceding_component.location.expression
        processed_source.comments.each do |comment|
          comment_expr = comment.location.expression
          distance = comment_expr.first_line - preceding_expr.first_line
          case distance
          when 0
            if comment_expr.last_line > preceding_expr.last_line ||
               comment_expr.end_pos > preceding_expr.end_pos
              preceding_expr = comment_expr
            end
          when 1
            preceding_expr = comment_expr
          end
        end

        stanza = stanza_text(name, value, indent: 2)
        tree_rewriter.insert_after(preceding_expr, "\n#{stanza}")
      end

      protected

      # Only declarations retained in the release template separate neighbouring patches.
      sig { returns(T::Hash[[Integer, T::Array[String]], T::Array[BlockNode]]) }
      def patches_by_scope
        omitted = tree_rewriter.as_replacements.filter_map { |range, replacement| range if replacement.empty? }
        position = 0
        groups = {}
        patch_scope_nodes.each do |node|
          if node.is_a?(BlockNode)
            next if PATCH_PLATFORM_BLOCKS.include?(node.method_name)

            if node.method?(:patch)
              scope = [position, node.each_ancestor(:block).map { |parent| parent.send_node.source }]
              (groups[scope] ||= []) << node
              next
            end
          end
          range = node.source_range
          position += 1 if omitted.none? { |removed| removed == range || removed.contains?(range) }
        end
        groups
      end

      sig { returns(T::Array[String]) }
      def retained_mirror_origins
        mirrors = stable_mirror_origins
        if mirrors.one?
          urls = stable_children.grep(SendNode).select { |call| call.receiver.nil? && call.method?(:url) }
          source = urls.fetch(0).first_argument&.str_content if urls.one?
          mirror = mirrors.fetch(0).first.first_argument&.str_content
          return [] if source && mirror && URL.automatic_mirror(source) == mirror
        end
        mirrors.map(&:last)
      end

      sig { returns(T::Array[[SendNode, String]]) }
      def stable_mirror_origins
        stable_children.grep(SendNode).filter_map do |node|
          next if node.receiver || !node.method?(:mirror) || !node.arguments.one?

          value = node.arguments.fetch(0)
          origin = value.str_content[BUMP_URL_ORIGIN] if value.str_type?
          [node, origin || node.source]
        end
      end

      private

      sig { params(patch: BlockNode, candidate: String).returns(T.nilable(T::Array[BlockNode])) }
      def prepared_patch_branches(patch, candidate)
        branches = patches_for_removal(patch) do |_urls, branch|
          branch.each_node(:block).none? { |part| candidate.include?(part.source) }
        end
        return if branches.empty? || branches.first.equal?(patch)

        remaining = patch.source.dup
        offset = patch.source_range.begin_pos
        branches.reverse_each do |branch|
          range = stanza_removal_range(branch, remove_leading_comments: true)
          remaining[(range.begin_pos - offset)...(range.end_pos - offset)] = ""
        end
        branches if remaining == candidate
      end

      sig { returns(String) }
      attr_reader :formula_contents

      sig { returns(ProcessedSource) }
      attr_reader :processed_source

      sig { returns(TreeRewriter) }
      attr_reader :tree_rewriter

      sig { params(nodes: T::Array[Node], name: Symbol, type: T.nilable(Symbol)).returns(T::Array[Node]) }
      def matching_stanzas(nodes, name, type: nil)
        nodes.select { |child| call_node_match?(child, name:, type:) }
      end

      sig { params(name: Symbol).returns(Node) }
      def stable_stanza(name)
        stanza_node = matching_stanzas(stable_children, name).first
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        stanza_node
      end

      sig {
        params(
          resource_name: String,
          name:          Symbol,
          old_value:     T.nilable(T.any(Numeric, String, Symbol)),
        ).returns(Node)
      }
      def resource_stanza(resource_name, name, old_value: nil)
        stanza_node = matching_stanzas(body_children(resource(resource_name).body), name).find do |node|
          old_value.nil? || literal_value(T.cast(node, T.any(SendNode, BlockNode)).first_argument) == old_value
        end
        raise "Could not find '#{name}' stanza in resource '#{resource_name}'!" if stanza_node.blank?

        stanza_node
      end

      sig { returns(T::Array[Node]) }
      def stable_children
        if (stable_node = stanza(:stable, type: :block_call))
          body_children(T.cast(stable_node, BlockNode).body)
        else
          children
        end
      end

      sig { params(stanza_node: Node, value: T.any(Numeric, String, Symbol)).void }
      def replace_stanza_value(stanza_node, value)
        stanza_node = T.cast(stanza_node, T.any(SendNode, BlockNode))
        argument = stanza_node.first_argument
        raise "Could not find '#{stanza_node.method_name}' stanza value!" if argument.blank?

        tree_rewriter.replace(argument.source_range, ruby_literal(value))
      end

      sig { params(stanza_node: Node, key: Symbol, value: T.any(Numeric, String, Symbol)).void }
      def replace_stanza_hash_value(stanza_node, key, value)
        stanza_node = T.cast(stanza_node, T.any(SendNode, BlockNode))
        pair = stanza_node.arguments.grep(RuboCop::AST::HashNode).flat_map(&:pairs).find do |hash_pair|
          literal_value(hash_pair.key) == key
        end
        raise "Could not find '#{key}' value in '#{stanza_node.method_name}' stanza!" if pair.blank?

        tree_rewriter.replace(pair.value.source_range, ruby_literal(value))
      end

      sig { params(stanza_node: Node, remove_leading_comments: T::Boolean).void }
      def remove_stanza_node(stanza_node, remove_leading_comments: false)
        tree_rewriter.remove(stanza_removal_range(stanza_node, remove_leading_comments:))
      end

      sig { params(stanza_node: Node, remove_leading_comments: T::Boolean).returns(Parser::Source::Range) }
      def stanza_removal_range(stanza_node, remove_leading_comments:)
        stanza_range = stanza_node.source_range
        if remove_leading_comments
          processed_source.comments.reverse_each do |comment|
            comment_range = comment.location.expression
            next if comment_range.last_line != stanza_range.first_line - 1
            next if comment_range.column != stanza_range.column

            stanza_range = stanza_range.with(begin_pos: comment_range.begin_pos)
          end
        end

        # stanza is probably followed by a newline character
        # try to delete it if so
        trailing_range = stanza_range.with(begin_pos: stanza_range.end_pos,
                                           end_pos:   stanza_range.end_pos + 1)
        if trailing_range.source.chomp.empty?
          stanza_range = stanza_range.adjust(end_pos: 1)

          # stanza_node is probably indented
          # since a trailing newline has been removed,
          # try to delete leading whitespace on line
          leading_range = stanza_range.with(begin_pos: stanza_range.begin_pos - stanza_range.column,
                                            end_pos:   stanza_range.begin_pos)
          if leading_range.source.strip.empty?
            stanza_range = stanza_range.adjust(begin_pos: -stanza_range.column)

            # if the stanza was preceded by a blank line, it should be removed
            # that is, if the two previous characters are newlines,
            # then delete one of them
            leading_range = stanza_range.with(begin_pos: stanza_range.begin_pos - 2,
                                              end_pos:   stanza_range.begin_pos)
            stanza_range = stanza_range.adjust(begin_pos: -1) if leading_range.source.chomp.chomp.empty?
          end
        end

        stanza_range
      end

      sig {
        params(
          range:                         Parser::Source::Range,
          include_following_blank_lines: T::Boolean,
        ).returns(Parser::Source::Range)
      }
      def whole_line_range(range, include_following_blank_lines: false)
        begin_pos = range.begin_pos - range.column
        end_pos = line_end_pos(range.end_pos)
        if include_following_blank_lines
          while end_pos < formula_contents.length
            next_line_end = line_end_pos(end_pos)
            break unless formula_contents[end_pos...next_line_end].to_s.strip.empty?

            end_pos = next_line_end
          end
        end
        range.with(begin_pos:, end_pos:)
      end

      sig { params(position: Integer).returns(Integer) }
      def line_end_pos(position)
        newline_pos = formula_contents.index("\n", position)
        newline_pos&.succ || formula_contents.length
      end

      sig { params(node: Node, target_name: Symbol, target_type: T.nilable(Symbol)).returns(T::Boolean) }
      def formula_component_before_target?(node, target_name:, target_type: nil)
        FORMULA_COMPONENT_PRECEDENCE_LIST.each do |components|
          return false if components.any? do |component|
            component_match?(component_name: component[:name],
                             component_type: component[:type],
                             target_name:,
                             target_type:)
          end
          return true if components.any? do |component|
            call_node_match?(node, name: component[:name], type: component[:type])
          end
        end

        false
      end
    end

    # Helper class for editing casks.
    class CaskAST
      include AST

      sig { params(cask_contents: String).void }
      def initialize(cask_contents)
        @cask_contents = cask_contents
        processed_source, root_node = process_source(cask_contents)
        cask_block = if root_node.block_type? && T.cast(root_node, BlockNode).method_name == :cask
          T.cast(root_node, BlockNode)
        elsif root_node.begin_type?
          root_node.children.find { |node| node.block_type? && node.method_name == :cask }
        end

        raise "Could not find cask block!" if cask_block.nil?

        @processed_source = T.let(processed_source, ProcessedSource)
        @cask_block = T.let(T.cast(cask_block, BlockNode), BlockNode)
        @tree_rewriter = T.let(TreeRewriter.new(processed_source.buffer), TreeRewriter)
      end

      # Compare a prepared cask with the release edits allowed in its checkout.
      sig { params(original: String, proposed: String, version: String).returns(T::Boolean) }
      def self.valid_bump?(original, proposed, version:)
        checkout = new(original)
        proposal = new(proposed)
        # `brew audit --fix` may have corrected the minimum macOS version.
        minimum = proposal.depends_on_macos_value
        if minimum.is_a?(RuboCop::AST::SymbolNode) && !checkout.update_depends_on_macos_minimum!(minimum.value)
          return false
        end

        old_values = checkout.blank_bump_values!
        new_values = proposal.blank_bump_values!
        return false if checkout.process != proposal.process
        return false unless new_values.fetch(:sha256).all? { |checksum| checksum.match?(/\A\h{64}\z/) }

        require "livecheck/livecheck_version"

        livecheck_version = lambda do |value|
          Homebrew::Livecheck::LivecheckVersion.new(value.to_s.split(",").map { |part| Version.new(part) })
        end
        bumps = old_values.fetch(:version).zip(new_values.fetch(:version)).reject { |current, bump| current == bump }
        bumps.any? { |_, bump| bump == version } && bumps.all? do |current, bump|
          bump.to_s.match?(/\A[[:alnum:]][[:alnum:].,:+_-]*\z/) &&
            livecheck_version.call(bump) > livecheck_version.call(current)
        end
      end

      sig { returns(String) }
      def process
        tree_rewriter.process
      end

      # Blank the version and checksum strings replaced by a bump and return them by stanza.
      sig { returns(T::Hash[Symbol, T::Array[String]]) }
      def blank_bump_values!
        [:version, :sha256].to_h do |name|
          values = stanzas(name).flat_map do |stanza|
            stanza.arguments.flat_map do |argument|
              argument.is_a?(RuboCop::AST::HashNode) ? argument.pairs.map(&:value) : [argument]
            end
          end.select(&:str_type?)
          values.each { |value| tree_rewriter.replace(value.source_range, '""') }
          [name, values.map(&:str_content)]
        end
      end

      sig { params(name: Symbol, value: T.any(Numeric, String, Symbol)).void }
      def replace_first_stanza_value(name, value)
        stanza_node = stanzas(name).first
        raise "Could not find '#{name}' stanza!" if stanza_node.blank?

        replace_stanza_argument(stanza_node, value)
      end

      sig { params(name: Symbol, within: T.nilable(Symbol)).returns(T::Boolean) }
      def stanza?(name, within: nil)
        stanzas(name, within:).present?
      end

      sig { params(name: Symbol, within: Symbol).returns(T::Boolean) }
      def stanza_anywhere?(name, within:)
        cask_block.each_node(:block).any? do |node|
          block_node = T.cast(node, BlockNode)
          next false if block_node.method_name != within || block_node.receiver.present?

          block_node.each_node(:send).any? do |send_node|
            send_node.method_name == name && send_node.receiver.nil? && send_node.first_argument.present?
          end
        end
      end

      sig { params(name: Symbol, within: T.nilable(Symbol)).returns(T.untyped) }
      def first_stanza_value(name, within: nil)
        stanza_node = stanzas(name, within:).first
        return if stanza_node.blank?

        literal_value(stanza_node.first_argument)
      end

      sig {
        params(
          name:      Symbol,
          old_value: T.any(Numeric, String, Symbol),
          new_value: T.any(Numeric, String, Symbol),
          within:    T.nilable(Symbol),
        ).returns(Integer)
      }
      def replace_stanza_value(name, old_value, new_value, within: nil)
        replacement_count = T.let(0, Integer)
        stanzas(name, within:).each do |stanza_node|
          if literal_value(stanza_node.first_argument) == old_value
            replace_stanza_argument(stanza_node, new_value)
            replacement_count += 1
          end

          stanza_node.arguments.grep(RuboCop::AST::HashNode).each do |hash_node|
            hash_node.pairs.each do |pair|
              next if literal_value(pair.value) != old_value

              tree_rewriter.replace(pair.value.source_range, ruby_literal(new_value))
              replacement_count += 1
            end
          end
        end

        replacement_count
      end

      sig { params(name: Symbol, old_value: T.any(Numeric, String, Symbol)).void }
      def replace_root_stanza_with_arch_blocks(name, old_value)
        stanza_node = top_level_stanzas(name).find do |node|
          literal_value(node.first_argument) == old_value
        end
        return if stanza_node.blank?

        indent = " " * stanza_node.source_range.column
        replacement = <<~EOS
          #{indent}on_arm do
          #{indent}  #{name} #{ruby_literal(old_value)}
          #{indent}end
          #{indent}on_intel do
          #{indent}  #{name} #{ruby_literal(old_value)}
          #{indent}end
        EOS
        tree_rewriter.replace(whole_line_range(stanza_node.source_range), replacement)
      end

      sig { returns(T::Boolean) }
      def depends_on_macos?
        stanzas(:depends_on).any? do |stanza_node|
          stanza_node.arguments.any? do |argument|
            literal_value(argument) == :macos ||
              (argument.hash_type? && T.cast(argument, RuboCop::AST::HashNode).pairs.any? do |pair|
                literal_value(pair.key) == :macos
              end)
          end
        end
      end

      # The value of the top-level `depends_on macos:` stanza.
      sig { returns(T.nilable(Node)) }
      def depends_on_macos_value
        top_level_stanzas(:depends_on).flat_map { |stanza| stanza.arguments.grep(RuboCop::AST::HashNode) }
                                      .flat_map(&:pairs)
                                      .find { |pair| literal_value(pair.key) == :macos }
                                      &.value
      end

      # Sets the minimum macOS version of the `depends_on macos:` stanza, adding
      # the stanza when it is missing. Returns `false` when the minimum version
      # cannot be expressed, e.g. an exact version list or a maximum.
      sig { params(version: Symbol).returns(T::Boolean) }
      def update_depends_on_macos_minimum!(version)
        if (macos_value = depends_on_macos_value)
          return false unless minimum_macos_value?(macos_value)

          tree_rewriter.replace(macos_value.source_range, ruby_literal(version))
          return true
        end

        # A second stanza alongside a bare `depends_on :macos` would be flagged
        # as redundant by `Homebrew/OSDependsOn`.
        bare_stanza_node = top_level_stanzas(:depends_on).find do |node|
          argument = node.first_argument
          argument&.sym_type? && literal_value(argument) == :macos
        end
        if (bare_argument = bare_stanza_node&.first_argument)
          tree_rewriter.replace(bare_argument.source_range, "macos: #{ruby_literal(version)}")
          return true
        end

        return false if depends_on_macos?

        new_stanza = "depends_on macos: #{ruby_literal(version)}"

        if (existing_stanza = top_level_stanzas(:depends_on).last)
          indent = " " * existing_stanza.source_range.column
          tree_rewriter.insert_after(whole_line_range(existing_stanza.source_range), "#{indent}#{new_stanza}\n")
          return true
        end

        successor = stanza_successor(:depends_on)
        return false if successor.nil?

        indent = " " * successor.source_range.column
        line_range = whole_line_range(successor.source_range)
        separator = "\n" unless cask_contents[0...line_range.begin_pos].to_s.match?(/(\n\n|do\n)\z/)
        tree_rewriter.insert_before(line_range, "#{separator}#{indent}#{new_stanza}\n\n")
        true
      end

      private

      sig { returns(String) }
      attr_reader :cask_contents

      sig { returns(ProcessedSource) }
      attr_reader :processed_source

      sig { returns(BlockNode) }
      attr_reader :cask_block

      sig { returns(TreeRewriter) }
      attr_reader :tree_rewriter

      sig { params(name: Symbol, within: T.nilable(Symbol)).returns(T::Array[SendNode]) }
      def stanzas(name, within: nil)
        if within == :root
          nodes = body_children(cask_block.body).grep(SendNode)
        elsif within
          blocks = on_system_blocks(within)
          return [] if blocks.blank?

          nodes = blocks.flat_map { |block| body_children(block.body).grep(SendNode) }
        else
          nodes = cask_block.each_node(:send)
        end

        nodes.select do |node|
          node.method_name == name && node.receiver.nil? && node.first_argument.present?
        end
      end

      sig { params(name: Symbol).returns(T::Array[SendNode]) }
      def top_level_stanzas(name)
        body_children(cask_block.body).grep(SendNode).select do |node|
          node.method_name == name && node.receiver.nil? && node.first_argument.present?
        end
      end

      # Only a bare symbol or a `>=` comparison states a minimum macOS version.
      sig { params(node: Node).returns(T::Boolean) }
      def minimum_macos_value?(node)
        return true if node.sym_type?
        return false unless node.str_type?

        node.str_content&.match?(/\A\s*>=/) || false
      end

      # The first top-level stanza which must be ordered after `name`.
      sig { params(name: Symbol).returns(T.nilable(SendNode)) }
      def stanza_successor(name)
        stanza_order = RuboCop::Cask::Constants::STANZA_ORDER
        index = stanza_order.index(name)
        return if index.nil?

        body_children(cask_block.body).grep(SendNode).find do |node|
          successor_index = stanza_order.index(node.method_name)
          successor_index.present? && successor_index > index
        end
      end

      sig { params(name: Symbol).returns(T::Array[BlockNode]) }
      def on_system_blocks(name)
        body_children(cask_block.body).grep(BlockNode).select do |node|
          node.method_name == name && node.receiver.nil?
        end
      end

      sig { params(stanza_node: SendNode, value: T.any(Numeric, String, Symbol)).void }
      def replace_stanza_argument(stanza_node, value)
        argument = stanza_node.first_argument
        raise "Could not find '#{stanza_node.method_name}' stanza value!" if argument.blank?

        tree_rewriter.replace(argument.source_range, ruby_literal(value))
      end

      sig { params(range: Parser::Source::Range).returns(Parser::Source::Range) }
      def whole_line_range(range)
        range.with(
          begin_pos: range.begin_pos - range.column,
          end_pos:   line_end_pos(range.end_pos),
        )
      end

      sig { params(position: Integer).returns(Integer) }
      def line_end_pos(position)
        newline_pos = cask_contents.index("\n", position)
        newline_pos&.succ || cask_contents.length
      end
    end
  end
end
