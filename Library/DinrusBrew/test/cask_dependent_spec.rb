# frozen_string_literal: true

require "cask/cask_loader"
require "cask_dependent"

RSpec.describe CaskDependent, :needs_macos do
  subject(:dependent) { described_class.new test_cask }

  let :test_cask do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "testing" do
        depends_on formula: "baz"
        depends_on cask: "foo-cask"
        depends_on macos: ">= :mojave"
      end
    RUBY
  end

  describe "#deps" do
    it "is the formula dependencies of the cask" do
      expect(dependent.deps.map(&:name))
        .to eq %w[baz]
    end
  end

  describe "#requirements" do
    it "is the requirements of the cask" do
      expect(dependent.requirements.map(&:name))
        .to eq %w[foo-cask macos]
    end
  end

  describe "#recursive_dependencies", :integration_test do
    it "is all the dependencies of the cask" do
      setup_test_formula "foo"
      setup_test_formula "bar"
      setup_test_formula "baz", <<-RUBY
        url "https://brew.sh/baz-1.0"
        depends_on "bar"
      RUBY

      expect(dependent.recursive_dependencies.map(&:name))
        .to eq(%w[foo bar baz])
    end
  end

  describe "#recursive_requirements", :integration_test do
    it "is all the dependencies of the cask" do
      setup_test_formula "foo"
      setup_test_formula "bar"
      setup_test_formula "baz", <<-RUBY
        url "https://brew.sh/baz-1.0"
        depends_on "bar"
      RUBY

      expect(dependent.recursive_requirements.map(&:name))
        .to eq(%w[foo-cask macos])
    end
  end
end
