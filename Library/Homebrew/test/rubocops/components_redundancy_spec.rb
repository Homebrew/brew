# frozen_string_literal: true

require "rubocops/components_redundancy"

describe RuboCop::Cop::FormulaAudit::ComponentsRedundancy do
  subject(:cop) { described_class.new }

  context "when auditing formula components" do
    it "reports an offense if `url` is outside `stable` block" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ComponentsRedundancy: `url` should be put inside `stable` block
          stable do
            # stuff
          end

          head do
            # stuff
          end
        end
      RUBY
    end

    it "reports an offense if both `head` and `head do` are present" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          head "https://brew.sh/foo.git"
          head do
          ^^^^^^^ FormulaAudit/ComponentsRedundancy: `head` and `head do` should not be simultaneously present
            # stuff
          end
        end
      RUBY
    end

    it "reports an offense if both `bottle :modifier` and `bottle do` are present" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          bottle do
          ^^^^^^^^^ FormulaAudit/ComponentsRedundancy: `bottle :modifier` and `bottle do` should not be simultaneously present
            # bottles go here
          end
          bottle :unneeded
        end
      RUBY
    end

    it "reports no offenses if `stable do` is present with a `head` method" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          head "https://brew.sh/foo.git"

          stable do
            # stuff
          end
        end
      RUBY
    end

    it "reports no offenses if `stable do` is present with a `head do` block" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          stable do
            # stuff
          end

          head do
            # stuff
          end
        end
      RUBY
    end
  end
end
