# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/typecheck"

RSpec.describe Homebrew::DevCmd::Typecheck do
  it_behaves_like "parseable arguments"

  describe "#trim_rubocop_rbi" do
    let(:rbi_file) { Pathname.new("#{TEST_FIXTURE_DIR}/rubocop@x.x.x.rbi") }
    let(:typecheck) { described_class.new([]) }

    before do
      allow(Dir).to receive(:glob).and_return([rbi_file.to_s])
    end

    it "trims RuboCop RBI file to only include allowlisted classes" do
      old_content = rbi_file.read

      typecheck.trim_rubocop_rbi(path: rbi_file.to_s)

      new_content = rbi_file.read

      expect(new_content).to include("RuboCop::Config")
      expect(new_content).to include("RuboCop::Cop::Base")
      expect(new_content).to include("Parser::Source")
      expect(new_content).to include("VERSION")
      expect(new_content).to include("SOME_CONSTANT")
      expect(new_content).not_to include("SomeUnusedCop")
      expect(new_content).not_to include("UnusedModule")
      expect(new_content).not_to include("CompletelyUnrelated")

      rbi_file.write(old_content)
    end
  end
end
