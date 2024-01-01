# frozen_string_literal: true

shared_examples "formulae exist" do |array|
  array.each do |f|
    it "#{f} formula exists" do
      core_tap = Pathname("#{HOMEBREW_LIBRARY_PATH}/../Taps/homebrew/homebrew-core")
      formula_paths = core_tap.glob("Formula/**/#{f}.rb")
      alias_path = core_tap/"Aliases/#{f}"
      expect(formula_paths.any?(&:exist?) || alias_path.exist?).to be true
    end
  end
end
