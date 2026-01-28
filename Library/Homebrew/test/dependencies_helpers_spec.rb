# frozen_string_literal: true

require "dependencies_helpers"

RSpec.describe DependenciesHelpers do
  specify "#dependents" do
    foo = formula "foo" do
      url "foo"
      version "1.0"
    end

    foo_cask = Cask::CaskLoader.load(+<<-RUBY)
      cask "foo_cask" do
      end
    RUBY

    bar = formula "bar" do
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

    dependents = Class.new.extend(described_class).dependents([foo, foo_cask, bar, bar_cask])

    dependents.each do |dependent|
      methods.each do |method|
        expect(dependent.respond_to?(method))
          .to be true
      end
    end
  end
end
