# typed: true
# frozen_string_literal: true

require "rubocops/cmake_args"

RSpec.describe RuboCop::Cop::FormulaAudit::CMakeArgs do
  subject(:cop) { described_class.new }

  it "registers and corrects a positional CMake source directory" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", ".", *std_cmake_args
                          ^^^ FormulaAudit/CMakeArgs: Use explicit `-S` and `-B` arguments for CMake.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "-S", ".", "-B", ".", *std_cmake_args
        end
      end
    RUBY
  end

  it "registers and corrects a positional parent source directory" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "..", *std_cmake_args
                          ^^^^ FormulaAudit/CMakeArgs: Use explicit `-S` and `-B` arguments for CMake.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "-S", "..", "-B", ".", *std_cmake_args
        end
      end
    RUBY
  end

  it "registers and corrects a positional named source directory" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "src", *std_cmake_args
                          ^^^^^ FormulaAudit/CMakeArgs: Use explicit `-S` and `-B` arguments for CMake.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "-S", "src", "-B", ".", *std_cmake_args
        end
      end
    RUBY
  end

  it "does not register an offense for a non-literal source directory" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", buildpath, *std_cmake_args
        end
      end
    RUBY
  end

  it "does not register an offense for other CMake command modes" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "-E", "copy", "a", "b"
          system "cmake", "-P", "script.cmake"
        end
      end
    RUBY
  end

  it "accepts explicit CMake source and build directories" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "-S", ".", "-B", "build", *std_cmake_args
        end
      end
    RUBY
  end

  it "accepts an explicit in-source CMake build" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "-S", ".", "-B", ".", *std_cmake_args
        end
      end
    RUBY
  end

  it "registers and adds only the source directory when a build directory is given" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", ".", "-B", "build", *std_cmake_args
                          ^^^ FormulaAudit/CMakeArgs: Use explicit `-S` and `-B` arguments for CMake.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "-S", ".", "-B", "build", *std_cmake_args
        end
      end
    RUBY
  end

  it "registers and adds only the source directory for a joined build directory" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", ".", "-Bbuild", *std_cmake_args
                          ^^^ FormulaAudit/CMakeArgs: Use explicit `-S` and `-B` arguments for CMake.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "-S", ".", "-Bbuild", *std_cmake_args
        end
      end
    RUBY
  end

  it "does not register an offense for a joined source directory" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", ".", "-Ssrc", *std_cmake_args
        end
      end
    RUBY
  end

  it "does not register an offense when an explicit source directory is already passed" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", ".", "-S", "src", *std_cmake_args
        end
      end
    RUBY
  end

  it "does not treat a CMake build command as a source directory" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          system "cmake", "--build", "."
        end
      end
    RUBY
  end

  it "does not register an offense for a system method with a receiver" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        def install
          runner.system "cmake", "."
        end
      end
    RUBY
  end
end
