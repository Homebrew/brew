# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Flags the `T.untyped` a `sig` gives a keyword rest parameter such as `**options`. Sorbet
      # checks no keyword passed to such a method, so a mistyped one only fails at runtime, in
      # whichever code path reaches it. Name the keywords the method accepts instead.
      #
      # Where arbitrary keywords are the point, such as stdlib options or API query parameters,
      # type the values `T.anything` so the method has to narrow them before use. Disable it on
      # the `sig` line, with a comment saying why, where neither fits.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # sig { params(args: String, options: T.untyped).returns(SystemCommand::Result) }
      # def curl(*args, **options)
      #   curl_with_workarounds(*args, **options)
      # end
      #
      # # good
      # sig { params(args: String, secrets: T::Array[String]).returns(SystemCommand::Result) }
      # def curl(*args, secrets: [])
      #   curl_with_workarounds(*args, secrets:)
      # end
      # ```
      class NoUntypedKeywordRest < Base
        MSG = "Replace `**%<name>s` typed `T.untyped` with explicit keyword arguments so Sorbet checks them."

        # The forms `RuboCop::Cop::Sorbet::SignatureHelp#signature?` matches. Tapioca excludes
        # `rubocop-sorbet`, so its mixin has no RBI to include it under `typed: strict`.
        def_node_matcher :signature?, <<~PATTERN
          (block
            (send
              {nil? (const (const {nil? cbase} :T) :Sig) (const (const (const {nil? cbase} :T) :Sig) :WithoutRuntime)}
              :sig (sym :final)?)
            (args) ...)
        PATTERN

        def_node_matcher :untyped_param_type, <<~PATTERN
          (send _ :params (hash <(pair (sym %1) $(send (const {nil? cbase} :T) :untyped)) ...>))
        PATTERN

        sig { params(node: RuboCop::AST::DefNode).void }
        def on_def(node)
          keyword_rest = node.arguments.find(&:kwrestarg_type?)
          # An anonymous `**` has no name for a `sig` to type.
          name = keyword_rest&.name
          return if name.nil?

          parent = node.parent
          # `private def foo` and `private_class_method def self.foo` wrap the definition in a send.
          definition = (parent.is_a?(RuboCop::AST::SendNode) && parent.adjacent_def_modifier?) ? parent : node
          # `left_sibling` scans every sibling, so only reach it for a named `**`.
          signature = definition.left_sibling
          return if !signature.is_a?(RuboCop::AST::BlockNode) || !signature?(signature)

          # Follow the builder chain so a `T.proc.params` nested in the hash is never reached.
          builder = T.let(signature.body, T.nilable(RuboCop::AST::Node))
          builder = builder.receiver while builder.is_a?(RuboCop::AST::SendNode) && !builder.method?(:params)
          untyped_type = untyped_param_type(builder, name) if builder
          return if untyped_type.nil?

          add_offense(untyped_type, message: format(MSG, name:))
        end
        alias on_defs on_def
      end
    end
  end
end
