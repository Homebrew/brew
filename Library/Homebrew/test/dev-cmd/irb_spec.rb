# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/irb"

RSpec.describe Homebrew::DevCmd::Irb do
  it_behaves_like "parseable arguments"

  it "disables the Pry option" do
    expect { described_class.new(["--pry"]) }
      .to raise_error(MethodDeprecatedError, /disabled.*default IRB backend.*Pry is largely unmaintained upstream/i)
  end

  describe "integration test" do
    let(:history_file) { Pathname("#{Dir.home}/.brew_irb_history") }

    after do
      history_file.delete if history_file.exist?
    end

    it "starts an interactive Homebrew shell session", :integration_test do
      setup_test_formula "testball"

      irb_test = HOMEBREW_TEMP/"irb-test.rb"
      irb_test.write <<~RUBY
        "testball".f
        :testball.f
        exit
      RUBY

      # Coverage integration tests can load `io-console` before `irb`; Linux
      # may warn when `irb` loads the native extension again.
      expect { brew "irb", irb_test }
        .to output(/Interactive Homebrew Shell.*<Formula testball \(stable\)/m).to_stdout
        .and be_a_success

      # TODO: newer Ruby only supports history saving in interactive sessions
      #       and not if you feed in data from a file or stdin like we are doing here.
      #       The test will need to be adjusted for this to work.
      # expect(history_file).to exist
    end
  end
end
