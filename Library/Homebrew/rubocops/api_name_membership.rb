# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Enforces the use of `Homebrew::API.formula_name?`/`Homebrew::API.cask_token?`
      # over membership checks on `Homebrew::API.formula_names`/`Homebrew::API.cask_tokens`,
      # which allocate and linearly scan an array of every name in the API.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # Homebrew::API.formula_names.include?(name)
      # Homebrew::API.cask_tokens.exclude?(token)
      #
      # # good
      # Homebrew::API.formula_name?(name)
      # !Homebrew::API.cask_token?(token)
      # ```
      class ApiNameMembership < Base
        extend AutoCorrector

        MSG = "Use `Homebrew::API.%<predicate>s` instead of scanning `Homebrew::API.%<list>s`."

        RESTRICT_ON_SEND = [:include?, :exclude?].freeze

        PREDICATES = T.let({
          formula_names: "formula_name?",
          cask_tokens:   "cask_token?",
        }.freeze, T::Hash[Symbol, String])

        def_node_matcher :api_name_membership?, <<~PATTERN
          (send
            (send
              $(const (const {nil? cbase} :Homebrew) :API) ${:formula_names :cask_tokens})
            {:include? :exclude?} $_)
        PATTERN

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return unless (api, list, arg = api_name_membership?(node))

          predicate = PREDICATES.fetch(list)
          add_offense(node, message: format(MSG, predicate:, list:)) do |corrector|
            negation = (node.method_name == :exclude?) ? "!" : ""
            corrector.replace(node, "#{negation}#{api.source}.#{predicate}(#{arg.source})")
          end
        end
      end
    end
  end
end
