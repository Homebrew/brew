# typed: strict
# frozen_string_literal: true

# This follows the docs at https://github.com/lsegal/yard/blob/main/docs/Templates.md#setuprb
# rubocop:disable Style/TopLevelMethodDefinition
sig { void }
def init
  # `sorbet` is available transitively through the `yard-sorbet` plugin, but we're
  # outside of the standalone sorbet config, so `checked` is enabled by default
  T.bind(self, T.all(T::Class[T.anything], YARD::Templates::Template), checked: false)
  super

  return if sections.empty?

  sections[:index].place(:internal).before(:private)
end

sig { returns(T.nilable(String)) }
def internal
  T.bind(self, YARD::Templates::Template, checked: false)
  erb(:internal) if object.has_tag?(:api) && object.tag(:api).text == "internal"
end
# rubocop:enable Style/TopLevelMethodDefinition
