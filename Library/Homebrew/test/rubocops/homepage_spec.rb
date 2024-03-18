# frozen_string_literal: true

require "rubocops/homepage"

RSpec.describe RuboCop::Cop::FormulaAudit::Homepage do
  subject(:cop) { described_class.new }

  context "when auditing homepage" do
    it "reports an offense when there is no homepage" do
      expect_offense(<<~RUBY)
        class Foo < Formula
        ^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: Formula should have a homepage.
          url 'https://brew.sh/foo-1.0.tgz'
        end
      RUBY
    end

    it "reports an offense when the homepage is not HTTP or HTTPS" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "ftp://brew.sh/foo"
                   ^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: The homepage should start with http or https.
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY
    end

    it "reports an offense for freedesktop.org wiki pages" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "http://www.freedesktop.org/wiki/bar"
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: Freedesktop homepages should be styled `https://wiki.freedesktop.org/project_name`
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY
    end

    it "reports an offense for freedesktop.org software wiki pages" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "http://www.freedesktop.org/wiki/Software/baz"
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: Freedesktop homepages should be styled `https://wiki.freedesktop.org/www/Software/project_name`
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY
    end

    it "reports and corrects Google Code homepages" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://code.google.com/p/qux"
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: Google Code homepages should end with a slash
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://code.google.com/p/qux/"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY
    end

    it "reports and corrects GitHub homepages" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://github.com/foo/bar.git"
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: GitHub homepages should not end with .git
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://github.com/foo/bar"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY
    end

    describe "for Sourceforge" do
      correct_formula = <<~RUBY
        class Foo < Formula
          homepage "https://foo.sourceforge.io/"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      it "reports and corrects [1]" do
        expect_offense(<<~RUBY)
          class Foo < Formula
            homepage "http://foo.sourceforge.net/"
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: Sourceforge homepages should be `https://foo.sourceforge.io/`
            url "https://brew.sh/foo-1.0.tgz"
          end
        RUBY

        expect_correction(correct_formula)
      end

      it "reports and corrects [2]" do
        expect_offense(<<~RUBY)
          class Foo < Formula
            homepage "http://foo.sourceforge.net"
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: Sourceforge homepages should be `https://foo.sourceforge.io/`
            url "https://brew.sh/foo-1.0.tgz"
          end
        RUBY

        expect_correction(correct_formula)
      end

      it "reports and corrects [3]" do
        expect_offense(<<~RUBY)
          class Foo < Formula
            homepage "http://foo.sf.net/"
                     ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: Sourceforge homepages should be `https://foo.sourceforge.io/`
            url "https://brew.sh/foo-1.0.tgz"
          end
        RUBY

        expect_correction(correct_formula)
      end
    end

    it "reports and corrects readthedocs.org pages" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://foo.readthedocs.org"
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Homepage: Readthedocs homepages should be `https://foo.readthedocs.io`
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://foo.readthedocs.io"
          url "https://brew.sh/foo-1.0.tgz"
        end
      RUBY
    end

    it "reports an offense for HTTP homepages" do
      formula_homepages = {
        "sf"     => "http://foo.sourceforge.io/",
        "corge"  => "http://savannah.nongnu.org/corge",
        "grault" => "http://grault.github.io/",
        "garply" => "http://www.gnome.org/garply",
        "waldo"  => "http://www.gnu.org/waldo",
        "dotgit" => "http://github.com/quux",
      }

      formula_homepages.each do |name, homepage|
        source = <<~RUBY
          class #{name.capitalize} < Formula
            homepage "#{homepage}"
            url "https://brew.sh/#{name}-1.0.tgz"
          end
        RUBY

        expected_offenses = [{  message:  "FormulaAudit/Homepage: Please use https:// for #{homepage}",
                                severity: :convention,
                                line:     2,
                                column:   11,
                                source: }]

        expected_offenses.zip([inspect_source(source).last]).each do |expected, actual|
          expect(actual.message).to eq(expected[:message])
          expect(actual.severity).to eq(expected[:severity])
          expect(actual.line).to eq(expected[:line])
          expect(actual.column).to eq(expected[:column])
        end
      end
    end
  end
end
