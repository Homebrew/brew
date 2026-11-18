# typed: strict
# frozen_string_literal: true

require "dependencies_helpers"

RSpec.describe DependenciesHelpers do
  # Sorbet only resolves `dependents` below from a constant literal.
  include DependenciesHelpers # rubocop:disable RSpec/DescribedClass

  specify "#recursive_dep_includes keeps direct test dependencies after expanding a dependent" do
    bar = formula "bar" do
      T.bind(self, T.class_of(Formula))
      url "bar-1.0"
    end
    foo = formula "foo" do
      T.bind(self, T.class_of(Formula))
      url "foo-1.0"
      depends_on "bar" => :test
    end
    baz = formula "baz" do
      T.bind(self, T.class_of(Formula))
      url "baz-1.0"
      depends_on "foo"
    end
    [bar, foo].each { |f| stub_formula_loader(f) }
    includes = [:required?, :recommended?, :test?]
    recursive_dep_includes(baz, includes, [])

    expect(recursive_dep_includes(foo, includes, []).map(&:name)).to eq(["bar"])
  end

  specify "#dependents" do
    foo = formula "foo" do
      T.bind(self, T.class_of(Formula))
      url "foo"
      version "1.0"
    end

    foo_cask = Cask::CaskLoader.from_content(+<<-RUBY)
      cask "foo_cask" do
      end
    RUBY

    bar = formula "bar" do
      T.bind(self, T.class_of(Formula))
      url "bar-url"
      version "1.0"
    end

    bar_cask = Cask::CaskLoader.from_content(+<<-RUBY)
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
