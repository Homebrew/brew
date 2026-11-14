# typed: strict
# frozen_string_literal: true

require "rubocops/components_redundancy"

RSpec.describe RuboCop::Cop::FormulaAudit::ComponentsRedundancy do
  sig { returns(RuboCop::Cop::FormulaAudit::ComponentsRedundancy) }
  subject(:cop) { described_class.new }

  context "when auditing formula components" do
    it "reports and corrects an offense if both `sha256` and git `revision` are defined" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo.git",
              tag:      "1.0.0",
              revision: "0000000000000000000000000000000000000000"
          sha256 "586372eb92059873e29eba4f9dec8381541b4d3834660707faf8ba59146dfc35"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ComponentsRedundancy: Do not use both `sha256` and `revision:`.
          revision 1

          resource "bar" do
            url "git://brew.sh/bar", revision: "1111111111111111111111111111111111111111"
            version "0.1.0"
            sha256 "89fa3c95c329ec326e2e76493471a7a974c673792725059ef121e6f9efb05bf4"
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ComponentsRedundancy: Do not use both `sha256` and `revision:`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo.git",
              tag:      "1.0.0",
              revision: "0000000000000000000000000000000000000000"
          revision 1

          resource "bar" do
            url "git://brew.sh/bar", revision: "1111111111111111111111111111111111111111"
            version "0.1.0"
          end
        end
      RUBY
    end

    it "reports and corrects an offense if both `sha256` and git `revision` are defined in stable/head block" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          stable do
            url "https://brew.sh/foo.git",
                tag:      "1.0.0",
                revision: "0000000000000000000000000000000000000000"
            sha256 "586372eb92059873e29eba4f9dec8381541b4d3834660707faf8ba59146dfc35"
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ComponentsRedundancy: Do not use both `sha256` and `revision:`.

            resource "bar" do
              url "https://brew.sh/bar", using: :git, revision: "1111111111111111111111111111111111111111"
              sha256 "89fa3c95c329ec326e2e76493471a7a974c673792725059ef121e6f9efb05bf4"
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ComponentsRedundancy: Do not use both `sha256` and `revision:`.
            end
          end

          head do
            url "https://brew.sh/foo.git", branch: "develop"

            resource "bar" do
              url "git://brew.sh/bar", revision: "2222222222222222222222222222222222222222"
              sha256 "2c39089f64d9d4c3e632f120894b36b68dcc8ae8c6f5130c0c2e6f5bb7aebf2f"
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ComponentsRedundancy: Do not use both `sha256` and `revision:`.
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          stable do
            url "https://brew.sh/foo.git",
                tag:      "1.0.0",
                revision: "0000000000000000000000000000000000000000"

            resource "bar" do
              url "https://brew.sh/bar", using: :git, revision: "1111111111111111111111111111111111111111"
            end
          end

          head do
            url "https://brew.sh/foo.git", branch: "develop"

            resource "bar" do
              url "git://brew.sh/bar", revision: "2222222222222222222222222222222222222222"
            end
          end
        end
      RUBY
    end

    it "reports but does not correct an offense if `sha256` is used with a non-git url and `revision`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo", revision: "0000000000000000000000000000000000000000"
          sha256 "586372eb92059873e29eba4f9dec8381541b4d3834660707faf8ba59146dfc35"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ComponentsRedundancy: Do not use both `sha256` and `revision:`.
        end
      RUBY

      expect_no_corrections
    end

    it "reports no offenses if stable url uses `sha256` and resource uses git `revision`" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          sha256 "0000000000000000000000000000000000000000000000000000000000000000"
          revision 1

          resource "bar" do
            url "https://brew.sh/bar.git", revision: "1111111111111111111111111111111111111111"
          end
        end
      RUBY
    end

    it "reports no offenses if stable url uses `sha256` and resource uses git `revision` in stable/head block" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          stable do
            url "https://brew.sh/foo-1.0.tgz"
            sha256 "0000000000000000000000000000000000000000000000000000000000000000"

            resource "bar" do
              url "https://brew.sh/bar.git", revision: "1111111111111111111111111111111111111111"
            end
          end

          head do
            url "https://brew.sh/foo.git", branch: "develop"

            resource "bar" do
              url "https://brew.sh/bar", using: :git, revision: "2222222222222222222222222222222222222222"
            end
          end
        end
      RUBY
    end

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
          head "https://brew.sh/foo.git", branch: "develop"
          head do
          ^^^^^^^ FormulaAudit/ComponentsRedundancy: `head` and `head do` should not be simultaneously present
            # stuff
          end
        end
      RUBY
    end

    it "reports no offenses if `stable do` is present with a `head` method" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          head "https://brew.sh/foo.git", branch: "develop"

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

    it "reports an offense if `stable do` or `head do` is present with only `url`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          stable do
          ^^^^^^^^^ FormulaAudit/ComponentsRedundancy: `stable do` should not be present with only url/sha256/mirror/version
            url "https://brew.sh/foo-1.0.tgz"
          end

          head do
          ^^^^^^^ FormulaAudit/ComponentsRedundancy: `head do` should not be present with only url
            url "https://brew.sh/foo.git"
          end
        end
      RUBY
    end

    it "reports an offense if `head do` is present with only `url` and `branch`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"

          head do
          ^^^^^^^ FormulaAudit/ComponentsRedundancy: `head do` should not be present with only url
            url "https://brew.sh/foo.git", branch: "develop"
          end
        end
      RUBY
    end

    it "reports no offenses if `stable do` is present with `url` and `depends_on`" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          head "https://brew.sh/foo.git", branch: "trunk"

          stable do
            url "https://brew.sh/foo-1.0.tgz"
            depends_on "bar"
          end
        end
      RUBY
    end

    it "reports no offenses if `head do` is present with `url` and `depends_on`" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"

          head do
            url "https://brew.sh/foo.git", branch: "develop"
            depends_on "bar"
          end
        end
      RUBY
    end
  end
end
