# typed: strict
# frozen_string_literal: true

RSpec.shared_examples "formulae exist" do |array|
  T.bind(self, T.class_of(RSpec::Core::ExampleGroup))
  test_each(T.cast(array, T::Array[String])) do |name|
    it "#{name} formula exists" do
      T.bind(self, RSpec::Core::ExampleGroup)

      core = HOMEBREW_LIBRARY_PATH.parent/"Taps/homebrew/homebrew-core"
      if core.directory?
        expect((core/"Aliases"/name).file? || core.glob("Formula/**/#{name}.rb").any?(&:file?)).to be true
      else
        expect(Homebrew::API.formula_name?(name) || Homebrew::API.formula_aliases.key?(name)).to be true
      end
    end
  end
end
