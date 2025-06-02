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
          :desc, :homepage, :sha256, :url, :version
        ].freeze
        MESSAGE = "Do not use a top-level `%<stanza>s` stanza as the default. " \
                  "Add it to an `on_{system}` block instead. " \
                  "Use `:or_older` or `:or_newer` to specify a range of macOS versions."

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          cask_stanzas = cask_block.toplevel_stanzas

          return if (on_blocks = on_system_methods(cask_stanzas)).none?

          stanzas_in_blocks = on_system_stanzas(on_blocks)

          cask_stanzas.each do |stanza|
            # Skip if the stanza is not allowed to be overridden.
            next unless OVERRIDABLE_METHODS.include?(stanza.stanza_name)
            # Skip if the stanza outside of a block is not also in an `on_*` block.
            next unless stanzas_in_blocks.include?(stanza.stanza_name)

            add_offense(stanza.source_range, message: format(MESSAGE, stanza: stanza.stanza_name))
          end
        end

        sig { params(on_system: T::Array[RuboCop::Cask::AST::Stanza]).returns(T::Set[Symbol]) }
        def on_system_stanzas(on_system)
          names = T.let(Set.new, T::Set[Symbol])
          method_nodes = on_system.map(&:method_node)
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
