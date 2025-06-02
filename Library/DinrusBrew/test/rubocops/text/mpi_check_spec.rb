# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::MpiCheck do
  subject(:cop) { described_class.new }

  context "when auditing MPI dependencies" do
    it "reports and corrects an offense when using depends_on \"mpich\" in homebrew/core" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          depends_on "mpich"
          ^^^^^^^^^^^^^^^^^^ FormulaAudit/MpiCheck: Formulae in homebrew/core should use 'depends_on "open-mpi"' instead of 'depends_on "mpich"'.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          depends_on "open-mpi"
        end
      RUBY
    end
  end
end
