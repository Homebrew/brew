# frozen_string_literal: true

require "test_bot"
require "ostruct"

RSpec.describe Homebrew::TestBot::Setup do
  subject(:setup) { described_class.new }

  describe "#run!" do
    it "is successful" do
      expect(setup).to receive(:test)
        .exactly(3).times
        .and_return(instance_double(Homebrew::TestBot::Step, passed?: true))

      expect(setup.run!(args: instance_double(Homebrew::CLI::Args)).passed?).to be(true)
    end
  end
end
