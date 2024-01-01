# typed: true
# frozen_string_literal: true

def init
  # `sorbet` is available transitively through the `yard-sorbet` plugin, but we're
  # outside of the standalone sorbet config, so `checked` is enabled by default
  T.bind(self, T.all(Class, YARD::Templates::Template), checked: false)
  super

  return if sections.empty?

  sections[:index].place(:internal).before(:private)
end

def internal
  T.bind(self, YARD::Templates::Template, checked: false)
  erb(:internal) if object.has_tag?(:api) && object.tag(:api).text == "internal"
end
