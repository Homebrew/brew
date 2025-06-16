# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/irb"

RSpec.describe Homebrew::DevCmd::Irb do
  it_behaves_like "parseable arguments"

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

      expect { brew "irb", irb_test }
        .to output(/Interactive Homebrew Shell/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success

      # TODO: newer Ruby only supports history saving in interactive sessions
      # and not if you feed in data from a file or stdin like we are doing here.
      # The test will need to be adjusted for this to work.
      # expect(history_file).to exist
    end
  end
end
