# frozen_string_literal: true

require "rubocops/text"

RSpec.describe RuboCop::Cop::FormulaAudit::Text do
  subject(:cop) { described_class.new }

  context "when auditing formula text" do
    it 'reports an offense if `require "formula"` is present' do
      expect_offense(<<~RUBY)
        require "formula"
        ^^^^^^^^^^^^^^^^^ FormulaAudit/Text: `require "formula"` is now unnecessary
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"
        end
      RUBY
    end

    it "reports an offense if 'revision 0' is present" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"
          revision 0
          ^^^^^^^^^^ FormulaAudit/Text: `revision 0` is unnecessary
        end
      RUBY
    end

    it "reports an offense if both openssl and libressl are dependencies" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on "openssl"
          depends_on "libressl" => :optional
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Formulae should not depend on both OpenSSL and LibreSSL (even optionally).
        end
      RUBY

      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on "openssl"
          depends_on "libressl"
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Formulae should not depend on both OpenSSL and LibreSSL (even optionally).
        end
      RUBY
    end

    it "reports an offense if veclibfort is used instead of OpenBLAS (in homebrew/core)" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"
          depends_on "veclibfort"
          ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Formulae in homebrew/core should use OpenBLAS as the default serial linear algebra library.
        end
      RUBY
    end

    it "reports an offense if lapack is used instead of OpenBLAS (in homebrew/core)" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"
          depends_on "lapack"
          ^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Formulae in homebrew/core should use OpenBLAS as the default serial linear algebra library.
        end
      RUBY
    end

    it "reports an offense if `go get` is executed" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          def install
            system "go", "get", "bar"
            ^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Do not use `go get`. Please ask upstream to implement Go vendoring
          end
        end
      RUBY
    end

    it "reports an offense if `xcodebuild` is executed" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          def install
            system "xcodebuild", "foo", "bar"
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Use `xcodebuild *args` instead of `system 'xcodebuild', *args`
          end
        end
      RUBY
    end

    it "reports an offense if `def plist` is used" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          def install
            system "xcodebuild", "foo", "bar"
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Use `xcodebuild *args` instead of `system 'xcodebuild', *args`
          end

          def plist
          ^^^^^^^^^ FormulaAudit/Text: `def plist` is deprecated. Please use services instead: https://docs.brew.sh/Formula-Cookbook#service-files
            <<~XML
              <?xml version="1.0" encoding="UTF-8"?>
              <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
              <plist version="1.0">
              <dict>
                <key>Label</key>
                <string>org.nrpe.agent</string>
              </dict>
              </plist>
            XML
          end
        end
      RUBY
    end

    it 'reports an offense if `require "language/go"` is present' do
      expect_offense(<<~RUBY)
        require "language/go"
        ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: `require "language/go"` is no longer necessary or correct

        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          def install
            system "go", "get", "bar"
            ^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Do not use `go get`. Please ask upstream to implement Go vendoring
          end
        end
      RUBY
    end

    it "reports an offense if `Formula.factory(name)` is present" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          def install
            Formula.factory(name)
            ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: `Formula.factory(name)` is deprecated in favour of `Formula[name]`
          end
        end
      RUBY
    end

    it "reports an offense if `dep ensure` is used without `-vendor-only`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          def install
            system "dep", "ensure"
            ^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Use `"dep", "ensure", "-vendor-only"`
          end
        end
      RUBY
    end

    it "reports an offense if `cargo build` is executed" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          def install
            system "cargo", "build"
            ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Use `"cargo", "install", *std_cargo_args`
          end
        end
      RUBY
    end

    it "doesn't reports an offense if `cargo build` is executed with --lib" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          def install
            system "cargo", "build", "--lib"
          end
        end
      RUBY
    end

    it "reports an offense if `make` calls are not separated" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "make && make install"
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Use separate `make` calls
          end
        end
      RUBY
    end

    it "reports an offense if paths are concatenated in string interpolation" do
      expect_offense(<<~'RUBY')
        class Foo < Formula
          def install
            ohai "foo #{bar + "baz"}"
                      ^^^^^^^^^^^^^^ FormulaAudit/Text: Do not concatenate paths in string interpolation
          end
        end
      RUBY
    end

    it 'reports offenses if eg `lib+"thing"` is present' do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            (lib+"foo").install
             ^^^^^^^^^ FormulaAudit/Text: Use `lib/"foo"` instead of `lib+"foo"`
            (bin+"foobar").install
             ^^^^^^^^^^^^ FormulaAudit/Text: Use `bin/"foobar"` instead of `bin+"foobar"`
          end
        end
      RUBY
    end

    it 'reports an offense if `prefix + "bin"` is present' do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            ohai prefix + "bin"
                 ^^^^^^^^^^^^^^ FormulaAudit/Text: Use `bin` instead of `prefix + "bin"`
          end
        end
      RUBY

      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            ohai prefix + "bin/foo"
                 ^^^^^^^^^^^^^^^^^^ FormulaAudit/Text: Use `bin` instead of `prefix + "bin"`
          end
        end
      RUBY
    end
  end
end
