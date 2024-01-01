# frozen_string_literal: true

require "rubocops/class"

describe RuboCop::Cop::FormulaAuditStrict::TestPresent do
  subject(:cop) { described_class.new }

  it "reports an offense when there is no test block" do
    expect_offense(<<~RUBY)
      class Foo < Formula
      ^^^^^^^^^^^^^^^^^^^ A `test do` test block should be added
        url 'https://brew.sh/foo-1.0.tgz'
      end
    RUBY
  end
end
