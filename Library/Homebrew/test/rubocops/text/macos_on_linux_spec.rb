# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::MacOSOnLinux do
  subject(:cop) { described_class.new }

  it "reports an offense when `MacOS` is used in the `Formula` class" do
    expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        if MacOS::Xcode.version >= "12.0"
           ^^^^^ FormulaAudit/MacOSOnLinux: Don't use `MacOS` where it could be called on Linux.
          url 'https://brew.sh/linux-1.0.tgz'
        end
      end
    RUBY
  end

  it "reports an offense when `MacOS` is used in a `resource` block" do
    expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        url 'https://brew.sh/linux-1.0.tgz'

        resource "foo" do
          url "https://brew.sh/linux-1.0.tgz" if MacOS::full_version >= "12.0"
                                                 ^^^^^ FormulaAudit/MacOSOnLinux: Don't use `MacOS` where it could be called on Linux.
        end
      end
    RUBY
  end

  it "reports an offense when `MacOS` is used in an `on_linux` block" do
    expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        on_linux do
          if MacOS::Xcode.version >= "12.0"
             ^^^^^ FormulaAudit/MacOSOnLinux: Don't use `MacOS` where it could be called on Linux.
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      end
    RUBY
  end

  it "reports an offense when `MacOS` is used in an `on_arm` block" do
    expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        on_arm do
          if MacOS::Xcode.version >= "12.0"
             ^^^^^ FormulaAudit/MacOSOnLinux: Don't use `MacOS` where it could be called on Linux.
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      end
    RUBY
  end

  it "reports an offense when `MacOS` is used in an `on_intel` block" do
    expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        on_intel do
          if MacOS::Xcode.version >= "12.0"
             ^^^^^ FormulaAudit/MacOSOnLinux: Don't use `MacOS` where it could be called on Linux.
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      end
    RUBY
  end

  it "reports no offenses when `MacOS` is used in an `on_macos` block" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        on_macos do
          if MacOS::Xcode.version >= "12.0"
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      end
    RUBY
  end

  it "reports no offenses when `MacOS` is used in an `on_ventura` block" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        on_ventura :or_older do
          if MacOS::Xcode.version >= "12.0"
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      end
    RUBY
  end

  it "reports no offenses when `MacOS` is used in the `install` method" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        url 'https://brew.sh/linux-1.0.tgz'

        def install
          MacOS.version
        end
      end
    RUBY
  end

  it "reports no offenses when `MacOS` is used in the `test` block" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        desc "foo"
        url 'https://brew.sh/linux-1.0.tgz'

        test do
          MacOS.version
        end
      end
    RUBY
  end
end
