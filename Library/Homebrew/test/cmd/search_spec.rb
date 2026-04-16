# typed: false
# frozen_string_literal: true

require "cmd/search"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::SearchCmd do
  it_behaves_like "parseable arguments"

  it "finds formula in search", :integration_test, :no_api do
    setup_test_formula "testball"

    expect { brew "search", "testball" }
      .to output(/testball/).to_stdout
      .and be_a_success
  end

  describe "::print_missing_formula_help" do
    let(:search_cmd) { described_class.new([""]) }

    context "when $stdout is not a TTY" do
      before { allow_any_instance_of(StringIO).to receive(:tty?).and_return(false) }

      it "skips" do
        expect { search_cmd.send(:print_missing_formula_help, "formula", false) }
          .not_to output.to_stdout
      end
    end

    context "when $stdout is a TTY" do
      before { allow_any_instance_of(StringIO).to receive(:tty?).and_return(true) }

      it "skips a regex query" do
        expect { search_cmd.send(:print_missing_formula_help, "/formula/", false) }
          .not_to output.to_stdout
      end

      it "skips if there is not a reason" do
        allow(Homebrew::MissingFormula).to receive(:reason).and_return(nil)
        expect { search_cmd.send(:print_missing_formula_help, "formula", false) }
          .not_to output.to_stdout
      end

      it "prints additional output if `found_matches` is true" do
        allow(Homebrew::MissingFormula).to receive(:reason).and_return("Reason")
        expect { search_cmd.send(:print_missing_formula_help, "formula", true) }
          .to output("\nIf you meant \"formula\" specifically:\nReason\n").to_stdout
      end

      it "only prints reason if `found_matches` is false" do
        allow(Homebrew::MissingFormula).to receive(:reason).and_return("Reason")
        expect { search_cmd.send(:print_missing_formula_help, "formula", false) }
          .to output("Reason\n").to_stdout
      end
    end
  end
end
