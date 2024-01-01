# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew ruby" do
  it_behaves_like "parseable arguments"

  it "executes ruby code with Homebrew's libraries loaded", :integration_test do
    expect { brew "ruby", "-e", "exit 0" }
      .to be_a_success
      .and not_to_output.to_stdout
      .and not_to_output.to_stderr
  end

  # Doesn't actually need Linux but only running there as integration tests are slow.
  describe "-e 'puts \"testball\".f.path'", :integration_test, :needs_linux do
    let!(:target) do
      target_path = setup_test_formula "testball"
      { path: target_path }
    end

    it "prints the path of a test formula" do
      expect { brew "ruby", "-e", "puts 'testball'.f.path" }
        .to be_a_success
        .and output(/^#{target[:path]}$/).to_stdout
        .and not_to_output.to_stderr
    end
  end
end
