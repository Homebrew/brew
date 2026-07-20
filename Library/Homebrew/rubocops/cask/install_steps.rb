# typed: strict
# frozen_string_literal: true

require "rubocops/shared/install_steps_helper"

module RuboCop
  module Cop
    module Cask
      # This cop checks declarative install step usage.
      class InstallSteps < Base
        extend AutoCorrector
        include CaskHelp
        include ::RuboCop::Cop::InstallStepsHelper

        INSTALL_STEP_PAIRS = T.let(
          {
            preflight:            :preflight_steps,
            postflight:           :postflight_steps,
            uninstall_preflight:  :uninstall_preflight_steps,
            uninstall_postflight: :uninstall_postflight_steps,
          }.freeze,
          T::Hash[Symbol, Symbol],
        )
        KEYCHAIN_HASHES_SOURCE =
          'hashes = stdout.lines.grep(/^SHA-256 hash:/) { |l| l.split(":").second.strip }'
        KEYCHAIN_DELETE_SOURCE = T.let(
          <<~RUBY.gsub(/\s+/, " ").strip.freeze,
            hashes.each do |h|
              system_command "/usr/bin/security",
                             args: ["delete-certificate", "-Z", h],
                             sudo: true
            end
          RUBY
          String,
        )
        CERTIFICATE_EXISTS_GUARD_SOURCE = "next unless cert.exist?"
        CERTIFICATE_FINGERPRINT_SOURCE = T.let(
          <<~RUBY.gsub(/\s+/, " ").strip.freeze,
            stdout, * = system_command "/usr/bin/openssl",
                                       args: ["x509", "-fingerprint", "-sha256", "-noout", "-in", cert]
          RUBY
          String,
        )
        CERTIFICATE_HASH_SOURCE = 'hash = stdout.lines.first.split("=").second.delete(":").strip'
        CERTIFICATE_HASH_DELETE_SOURCE = T.let(
          <<~RUBY.gsub(/\s+/, " ").strip.freeze,
            if hashes.include?(hash)
              system_command "/usr/bin/security",
                             args: ["delete-certificate", "-Z", hash],
                             sudo: true
            end
          RUBY
          String,
        )

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          stanzas = cask_block.stanzas
          INSTALL_STEP_PAIRS.each do |flight_block, steps_block|
            next unless (flight_stanza = stanzas.find { |stanza| stanza.stanza_name == flight_block })

            steps_stanza = stanzas.find { |stanza| stanza.stanza_name == steps_block }
            audit_flight_block(flight_stanza, steps_block) if steps_stanza.nil?
          end

          stanzas.each do |stanza|
            next unless INSTALL_STEP_PAIRS.value?(stanza.stanza_name)
            next unless stanza.method_node.block_type?
            next unless (offense_node = install_step_block_offense_node(
              T.cast(stanza.method_node, RuboCop::AST::BlockNode),
              allowed_methods: CASK_ALLOWED_STEP_METHODS,
            ))

            add_offense(offense_node, message: step_block_msg(CASK_ALLOWED_STEP_METHODS))
          end
        end

        private

        sig { params(flight_stanza: RuboCop::Cask::AST::Stanza, steps_block: Symbol).void }
        def audit_flight_block(flight_stanza, steps_block)
          return unless flight_stanza.method_node.block_type?

          block_node = T.cast(flight_stanza.method_node, RuboCop::AST::BlockNode)
          step_lines = keychain_certificate_step_lines(block_node.body) ||
                       simple_install_step_lines(block_node.body,
                                                 default_base:        :staged_path,
                                                 default_source_base: :staged_path,
                                                 default_target_base: :staged_path,
                                                 rebuild_actions:     false,
                                                 permission_actions:  true)
          return if step_lines.blank?

          add_offense(block_node.source_range,
                      message: format(SIMPLE_STEP_CONVERSION_MSG, steps_block:)) do |corrector|
            corrector.replace(
              block_node.source_range,
              install_steps_block_source(steps_block, step_lines, block_node.source_range.column),
            )
          end
        end

        sig { params(body_node: T.nilable(RuboCop::AST::Node)).returns(T.nilable(T::Array[String])) }
        def keychain_certificate_step_lines(body_node)
          direct_nodes = direct_install_step_nodes(body_node)
          return fingerprint_keychain_step_lines(direct_nodes) if direct_nodes.length == 7

          if (name_node = keychain_delete_sequence_name(direct_nodes))&.str_type?
            return ["delete_keychain_certificates #{T.cast(name_node, RuboCop::AST::StrNode).str_content.inspect}"]
          end

          return if body_node.nil? || !body_node.block_type?

          block_node = T.cast(body_node, RuboCop::AST::BlockNode)
          send_node = block_node.send_node
          names_node = send_node.receiver
          return if send_node.method_name != :each || send_node.arguments.present? || !names_node&.array_type?

          block_arguments = block_node.arguments.children
          return if block_arguments.length != 1 || block_arguments.first&.children != [:cert_name]

          name_nodes = names_node.child_nodes
          return unless name_nodes.all?(&:str_type?)

          sequence_name_node = keychain_delete_sequence_name(direct_install_step_nodes(block_node.body))
          return unless sequence_name_node&.lvar_type?
          return if sequence_name_node.children != [:cert_name]

          name_nodes.map do |name|
            "delete_keychain_certificates #{T.cast(name, RuboCop::AST::StrNode).str_content.inspect}"
          end
        end

        sig { params(nodes: T::Array[RuboCop::AST::Node]).returns(T.nilable(RuboCop::AST::Node)) }
        def keychain_delete_sequence_name(nodes)
          return if nodes.length != 3

          name_node = keychain_find_certificate_name(nodes.fetch(0))
          return if name_node.nil?
          return if normalised_install_step_source(nodes.fetch(1)) != KEYCHAIN_HASHES_SOURCE
          return if normalised_install_step_source(nodes.fetch(2)) != KEYCHAIN_DELETE_SOURCE

          name_node
        end

        sig { params(nodes: T::Array[RuboCop::AST::Node]).returns(T.nilable(T::Array[String])) }
        def fingerprint_keychain_step_lines(nodes)
          path_node = certificate_path(nodes.fetch(0))
          return if path_node.nil?
          return if normalised_install_step_source(nodes.fetch(1)) != CERTIFICATE_EXISTS_GUARD_SOURCE

          fingerprint_source = normalised_install_step_source(nodes.fetch(2))
                               .gsub(/\[\s+/, "[")
                               .gsub(/\s+\]/, "]")
          return if fingerprint_source != CERTIFICATE_FINGERPRINT_SOURCE
          return if normalised_install_step_source(nodes.fetch(3)) != CERTIFICATE_HASH_SOURCE

          name_node = keychain_find_certificate_name(nodes.fetch(4))
          return if name_node.nil? || !name_node.str_type?
          return if normalised_install_step_source(nodes.fetch(5)) != KEYCHAIN_HASHES_SOURCE
          return if normalised_install_step_source(nodes.fetch(6)) != CERTIFICATE_HASH_DELETE_SOURCE

          name = T.cast(name_node, RuboCop::AST::StrNode).str_content.inspect
          path = T.cast(path_node, RuboCop::AST::StrNode).str_content.inspect
          source = <<~RUBY.chomp
            delete_keychain_certificates #{name},
                                         fingerprint_of: #{path}
          RUBY
          [source]
        end

        sig { params(node: RuboCop::AST::Node).returns(T.nilable(RuboCop::AST::Node)) }
        def keychain_find_certificate_name(node)
          return unless node.masgn_type?
          return if node.child_nodes.length != 2

          assignment = node.child_nodes.fetch(0)
          command_node = node.child_nodes.fetch(1)
          return if normalised_install_step_source(assignment) != "stdout, *"
          return unless command_node.send_type?

          command = T.cast(command_node, RuboCop::AST::SendNode)
          return if command.receiver || command.method_name != :system_command || command.arguments.length != 2
          return unless command.arguments.fetch(0).str_type?
          return if T.cast(command.arguments.fetch(0), RuboCop::AST::StrNode).str_content != "/usr/bin/security"

          options = command.arguments.fetch(1)
          return unless options.hash_type?

          pairs = T.cast(options, RuboCop::AST::HashNode).pairs
          return if pairs.length != 2 || pairs.any? { |pair| !pair.key.sym_type? }
          return if pairs.map { |pair| pair.key.value } != [:args, :sudo]
          return unless pairs.fetch(1).value.true_type?

          arguments = pairs.fetch(0).value
          return unless arguments.array_type?

          values = arguments.child_nodes
          return if values.length != 5

          fixed_value_nodes = [0, 1, 2, 4].map { |index| values.fetch(index) }
          return unless fixed_value_nodes.all?(&:str_type?)

          fixed_values = fixed_value_nodes.map do |value|
            T.cast(value, RuboCop::AST::StrNode).str_content
          end
          return if fixed_values != ["find-certificate", "-a", "-c", "-Z"]

          values.fetch(3)
        end

        sig { params(node: RuboCop::AST::Node).returns(T.nilable(RuboCop::AST::Node)) }
        def certificate_path(node)
          return unless node.lvasgn_type?
          return if node.children.first != :cert

          expand_node = node.child_nodes.first
          return unless expand_node&.send_type?

          expand = T.cast(expand_node, RuboCop::AST::SendNode)
          return if expand.method_name != :expand_path || expand.arguments.present?
          return unless expand.receiver&.send_type?

          pathname = T.cast(expand.receiver, RuboCop::AST::SendNode)
          return if pathname.receiver || pathname.method_name != :Pathname || pathname.arguments.length != 1

          path = pathname.arguments.fetch(0)
          path if path.str_type?
        end
      end
    end
  end
end
