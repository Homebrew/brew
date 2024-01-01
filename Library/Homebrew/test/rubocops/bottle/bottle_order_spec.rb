# frozen_string_literal: true

require "rubocops/bottle"

describe RuboCop::Cop::FormulaAudit::BottleOrder do
  subject(:cop) { described_class.new }

  it "reports no offenses for `bottle :unneeded`" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle :unneeded
      end
    RUBY
  end

  it "reports no offenses for a properly ordered bottle block" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 arm64_something_else: "aaaaaaaa"
          sha256 arm64_big_sur: "aaaaaaaa"
          sha256 big_sur: "faceb00c"
          sha256 catalina: "deadbeef"
        end
      end
    RUBY

    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 cellar: :any, arm64_something_else: "aaaaaaaa"
          sha256 cellar: :any_skip_relocation, arm64_big_sur: "aaaaaaaa"
          sha256 cellar: "/usr/local/Cellar", big_sur: "faceb00c"
          sha256 catalina: "deadbeef"
        end
      end
    RUBY
  end

  it "reports no offenses for a properly ordered bottle block with a single bottle" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          sha256 big_sur: "faceb00c"
        end
      end
    RUBY

    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          sha256 cellar: :any, big_sur: "faceb00c"
        end
      end
    RUBY
  end

  it "reports no offenses for a properly ordered bottle block with only arm/intel bottles" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 arm64_catalina: "aaaaaaaa"
          sha256 arm64_big_sur: "aaaaaaaa"
        end
      end
    RUBY

    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 arm64_big_sur: "aaaaaaaa"
        end
      end
    RUBY

    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 big_sur: "faceb00c"
          sha256 catalina: "deadbeef"
        end
      end
    RUBY

    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 big_sur: "faceb00c"
        end
      end
    RUBY
  end

  it "reports and corrects arm bottles below intel bottles" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
        ^^^^^^^^^ FormulaAudit/BottleOrder: ARM bottles should be listed before Intel bottles
          rebuild 4
          sha256 big_sur: "faceb00c"
          sha256 catalina: "deadbeef"
          sha256 arm64_big_sur: "aaaaaaaa"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 arm64_big_sur: "aaaaaaaa"
          sha256 big_sur: "faceb00c"
          sha256 catalina: "deadbeef"
        end
      end
    RUBY
  end

  it "reports and corrects multiple arm bottles below intel bottles" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
        ^^^^^^^^^ FormulaAudit/BottleOrder: ARM bottles should be listed before Intel bottles
          rebuild 4
          sha256 big_sur: "faceb00c"
          sha256 arm64_catalina: "aaaaaaaa"
          sha256 catalina: "deadbeef"
          sha256 arm64_big_sur: "aaaaaaaa"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 arm64_catalina: "aaaaaaaa"
          sha256 arm64_big_sur: "aaaaaaaa"
          sha256 big_sur: "faceb00c"
          sha256 catalina: "deadbeef"
        end
      end
    RUBY
  end

  it "reports and corrects arm bottles with cellars below intel bottles" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
        ^^^^^^^^^ FormulaAudit/BottleOrder: ARM bottles should be listed before Intel bottles
          rebuild 4
          sha256 cellar: "/usr/local/Cellar",  big_sur:        "faceb00c"
          sha256                               catalina:       "deadbeef"
          sha256 cellar: :any,                 arm64_big_sur:  "aaaaaaaa"
          sha256 cellar: :any_skip_relocation, arm64_catalina: "aaaaaaaa"
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          rebuild 4
          sha256 cellar: :any,                 arm64_big_sur:  "aaaaaaaa"
          sha256 cellar: :any_skip_relocation, arm64_catalina: "aaaaaaaa"
          sha256 cellar: "/usr/local/Cellar",  big_sur:        "faceb00c"
          sha256                               catalina:       "deadbeef"
        end
      end
    RUBY
  end

  it "reports and corrects arm bottles below intel bottles with old bottle syntax" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
        ^^^^^^^^^ FormulaAudit/BottleOrder: ARM bottles should be listed before Intel bottles
          cellar :any
          sha256 "faceb00c" => :big_sur
          sha256 "aaaaaaaa" => :arm64_big_sur
          sha256 "aaaaaaaa" => :arm64_catalina
          sha256 "deadbeef" => :catalina
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        bottle do
          cellar :any
          sha256 "aaaaaaaa" => :arm64_big_sur
          sha256 "aaaaaaaa" => :arm64_catalina
          sha256 "faceb00c" => :big_sur
          sha256 "deadbeef" => :catalina
        end
      end
    RUBY
  end
end
