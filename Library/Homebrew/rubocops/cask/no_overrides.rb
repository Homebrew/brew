# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      class NoOverrides < Base
        include CaskHelp

        # These stanzas can be overridden by `on_*` blocks, so take them into account.
        # TODO: Update this list if new stanzas are added to `Cask::DSL` that call `set_unique_stanza`.
        OVERRIDABLE_METHODS = [
          :appcast, :arch, :auto_updates, :conflicts_with, :container,
          :desc, :homepage, :os, :sha256, :url, :version
        ].freeze

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          message = "Do not use a top-level `%<stanza>s` stanza as the default. " \
                    "Add it to an `on_{system}` block instead. " \
                    "Use `:or_older` or `:or_newer` to specify a range of macOS versions."
          cask_stanzas = cask_block.toplevel_stanzas

          return if (on_blocks = on_system_methods(cask_stanzas)).none?

          stanzas_in_blocks = on_system_stanzas(on_blocks)

          cask_stanzas.each do |stanza|
            # Skip if the stanza is not allowed to be overridden.
            next unless OVERRIDABLE_METHODS.include?(stanza.stanza_name)
            # Skip if the stanza outside of a block is not also in an `on_*` block.
            next unless stanzas_in_blocks.include?(stanza.stanza_name)

            add_offense(stanza.source_range, message: format(message, stanza: stanza.stanza_name))
          end
        end

        sig { params(on_system: T::Array[RuboCop::Cask::AST::Stanza]).returns(T::Set[Symbol]) }
        def on_system_stanzas(on_system)
          message = "Do not use a `depends_on macos:` stanza inside an `on_{system}` block. " \
                    "Add it once to specify the oldest macOS supported by any version in the cask."
          names = T.let(Set.new, T::Set[Symbol])
          method_nodes = on_system.map(&:method_node)

          # Check if multiple `on_{system}` blocks have different `depends_on macos:` versions.
          # If so, this indicates architecture-specific requirements and is allowed.
          macos_versions = T.let([], T::Array[String])
          method_nodes.select(&:block_type?).each do |node|
            node.child_nodes.each do |child|
              child.each_node(:send) do |send_node|
                next if send_node.method_name != :depends_on

                macos_pair = send_node.arguments.first.pairs.find { |a| a.key.value == :macos }
                macos_versions << macos_pair.value.source if macos_pair
              end
            end
          end
          # Allow if there are multiple different macOS versions specified
          allow_macos_depends_in_blocks = macos_versions.size > 1 && macos_versions.uniq.size > 1

          method_nodes.select(&:block_type?).each do |node|
            node.child_nodes.each do |child|
              child.each_node(:send) do |send_node|
                # Skip (nested) `livecheck` block as its `url` is different
                # from a download `url`.
                next if send_node.method_name == :livecheck || inside_livecheck_defined?(send_node)
                # Skip string interpolations.
                if send_node.ancestors.drop_while { |a| !a.begin_type? }.any? { |a| a.dstr_type? || a.regexp_type? }
                  next
                end
                next if RuboCop::Cask::Constants::ON_SYSTEM_METHODS.include?(send_node.method_name)

                if send_node.method_name == :depends_on &&
                   send_node.arguments.first.pairs.any? { |a| a.key.value == :macos } &&
                   OnSystemConditionalsHelper::ON_SYSTEM_OPTIONS.map do |m|
                     :"on_#{m}"
                   end.include?(T.cast(node, RuboCop::AST::BlockNode).method_name) && !allow_macos_depends_in_blocks
                  # Allow `depends_on macos:` in multiple `on_{system}` blocks for architecture-specific requirements
                  add_offense(send_node.source_range, message:)
                end

                names.add(send_node.method_name)
              end
            end
          end
          names
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def inside_livecheck_defined?(node)
          single_stanza_livecheck_defined?(node) || multi_stanza_livecheck_defined?(node)
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def single_stanza_livecheck_defined?(node)
          node.parent.block_type? && node.parent.method_name == :livecheck
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def multi_stanza_livecheck_defined?(node)
          grandparent_node = node.parent.parent
          node.parent.begin_type? && grandparent_node.block_type? && grandparent_node.method_name == :livecheck
        end
      end
    end
  end
end
