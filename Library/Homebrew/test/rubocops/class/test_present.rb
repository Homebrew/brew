# frozen_string_literal: true

require "rubocops/class"

RSpec.describe RuboCop::Cop::FormulaAuditStrict::TestPresent do
  subject(:cop) { described_class.new }

  it "reports an offense when there is no test block" do
    expect_offense(<<~RUBY)
      class Foo < Formula
      ^^^^^^^^^^^^^^^^^^^ A `test do` test block should be added
        url 'https://brew.sh/foo-1.0.tgz'
      end
    RUBY
  end

  it "reports no offenses when there is no test block and formula is disabled" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'

        disable! date: "2024-07-03", because: :unsupported
      end
    RUBY
  end
end
