# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/which-formula"

RSpec.describe Homebrew::Cmd::WhichFormula do
  it_behaves_like "parseable arguments"

  describe "which_formula" do
    before do
      # Override DATABASE_FILE to use test environment's HOMEBREW_CACHE
      test_db_file = HOMEBREW_CACHE/"api"/described_class::ENDPOINT
      stub_const("#{described_class}::DATABASE_FILE", test_db_file)

      db = described_class::DATABASE_FILE
      db.dirname.mkpath
      db.write(<<~EOS)
        foo(1.0.0):foo2 foo3
        bar(1.2.3):
        baz(10.4):baz
      EOS
    end

    it "prints the formula name for a given binary", :integration_test do
      expect { brew_sh "which-formula", "--skip-update", "foo2" }.to output("foo\n").to_stdout
      expect { brew_sh "which-formula", "--skip-update", "baz" }.to output("baz\n").to_stdout
      expect { brew_sh "which-formula", "--skip-update", "bar" }.not_to output.to_stdout
    end
  end
end
