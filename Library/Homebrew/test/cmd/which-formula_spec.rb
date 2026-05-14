# typed: false
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
        qux(4.5.6):QUX
        quux:quux
      EOS
    end

    it "prints the formula name for a given binary", :integration_test do
      expect { brew "which-formula", "--skip-update", "foo2" }.to output(/==> foo2\nfoo\n/).to_stdout
      expect { brew "which-formula", "--skip-update", "baz" }.to output(/==> baz\nbaz\n/).to_stdout
      expect { brew "which-formula", "--skip-update", "QUX" }.to output(/==> QUX\nqux\n/).to_stdout
      expect { brew "which-formula", "--skip-update", "quux" }.to output(/==> quux\nquux\n/).to_stdout
    end

    it "suggests a similar binary when the query has no matches", :integration_test do
      expect { brew "which-formula", "--skip-update", "fooo" }
        .to output(/No formula provides the binary "fooo"\. Did you mean foo[23]/).to_stderr
        .and be_a_failure
    end

    it "fails silently for a binary not in the database and with no suggestions", :integration_test do
      expect { brew "which-formula", "--skip-update", "totallyunrelated" }
        .to output(/No formula provides the binary "totallyunrelated"\./).to_stderr
        .and be_a_failure
    end
  end
end
