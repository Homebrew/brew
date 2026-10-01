# typed: strict
# frozen_string_literal: true

require "dependencies_helpers"

RSpec.describe DependenciesHelpers do
  # Sorbet only resolves `dependents` below from a constant literal.
  include DependenciesHelpers # rubocop:disable RSpec/DescribedClass

  specify "#dependents" do
    foo = formula "foo" do
      T.bind(self, T.class_of(Formula))
      url "foo"
      version "1.0"
    end

    foo_cask = Cask::CaskLoader.load(+<<-RUBY)
      cask "foo_cask" do
      end
    RUBY

    bar = formula "bar" do
      T.bind(self, T.class_of(Formula))
      url "bar-url"
      version "1.0"
    end

    bar_cask = Cask::CaskLoader.load(+<<-RUBY)
      cask "bar-cask" do
      end
    RUBY

    methods = [
      :name,
      :full_name,
      :runtime_dependencies,
      :deps,
      :requirements,
      :recursive_dependencies,
      :recursive_requirements,
      :any_version_installed?,
    ]

    dependents([foo, foo_cask, bar, bar_cask]).each do |dependent|
      methods.each do |method|
        expect(dependent.respond_to?(method))
          .to be true
      end
    end
  end
end
