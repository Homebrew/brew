# typed: strict
# frozen_string_literal: true

require "rubocops/formula_path_methods"

RSpec.describe RuboCop::Cop::Homebrew::FormulaPathMethods, :config do
  it "registers an offense and corrects `Formula[]` opt path calls" do
    expect_offense(<<~RUBY)
      Formula["foo"].opt_bin/"foo"
      ^^^^^^^^^^^^^^^^^^^^^^ Use `Utils::Path.formula_opt_bin("foo")` instead of `Formula["foo"].opt_bin`.
    RUBY

    expect_correction(<<~RUBY)
      Utils::Path.formula_opt_bin("foo")/"foo"
    RUBY
  end

  it "registers an offense and corrects `Formula[]` opt path calls in formulae" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          Formula["foo"].opt_bin/"foo"
          ^^^^^^^^^^^^^^^^^^^^^^ Use `formula_opt_bin("foo")` instead of `Formula["foo"].opt_bin`.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        def install
          formula_opt_bin("foo")/"foo"
        end
      end
    RUBY
  end

  it "registers an offense and corrects `Formula[]` opt path calls in casks" do
    expect_offense(<<~RUBY)
      cask "foo" do
        postflight do
          Formula["foo"].opt_bin/"foo"
          ^^^^^^^^^^^^^^^^^^^^^^ Use `formula_opt_bin("foo")` instead of `Formula["foo"].opt_bin`.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      cask "foo" do
        postflight do
          formula_opt_bin("foo")/"foo"
        end
      end
    RUBY
  end

  it "registers an offense and corrects scoped formula helpers in service blocks" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        service do
          Utils::Path.formula_opt_bin("foo")/"foo"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `formula_opt_bin("foo")` instead of `Utils::Path.formula_opt_bin("foo")`.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        service do
          formula_opt_bin("foo")/"foo"
        end
      end
    RUBY
  end

  it "registers an offense and corrects `Formulary.factory` opt path calls" do
    expect_offense(<<~RUBY)
      Formulary.factory("foo").opt_prefix/"bin/foo"
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Utils::Path.formula_opt_prefix("foo")` instead of `Formulary.factory("foo").opt_prefix`.
    RUBY

    expect_correction(<<~RUBY)
      Utils::Path.formula_opt_prefix("foo")/"bin/foo"
    RUBY
  end

  it "registers an offense and corrects dynamic formula names" do
    expect_offense(<<~RUBY)
      Formula[python_dep].opt_libexec/"bin/python"
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Utils::Path.formula_opt_libexec(python_dep)` instead of `Formula[python_dep].opt_libexec`.
    RUBY

    expect_correction(<<~RUBY)
      Utils::Path.formula_opt_libexec(python_dep)/"bin/python"
    RUBY
  end

  it "registers an offense and corrects formula installed checks" do
    expect_offense(<<~RUBY)
      Formula["foo"].any_version_installed?
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Utils::Path.formula_any_version_installed?("foo")` instead of `Formula["foo"].any_version_installed?`.
    RUBY

    expect_correction(<<~RUBY)
      Utils::Path.formula_any_version_installed?("foo")
    RUBY
  end

  it "registers an offense and corrects formula installed checks in formulae" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        def install
          Formula["foo"].any_version_installed?
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `formula_any_version_installed?("foo")` instead of `Formula["foo"].any_version_installed?`.
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        def install
          formula_any_version_installed?("foo")
        end
      end
    RUBY
  end

  it "registers an offense and corrects cask installed checks" do
    expect_offense(<<~RUBY)
      Cask::Cask.new(cask_token).installed?
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Cask::Caskroom.cask_installed?(cask_token)` instead of `Cask::Cask.new(cask_token).installed?`.
    RUBY

    expect_correction(<<~RUBY)
      Cask::Caskroom.cask_installed?(cask_token)
    RUBY
  end

  it "registers an offense and corrects cask any-version installed checks" do
    expect_offense(<<~RUBY)
      Cask::Cask.new(cask_token).any_version_installed?
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Cask::Caskroom.cask_installed?(cask_token)` instead of `Cask::Cask.new(cask_token).any_version_installed?`.
    RUBY

    expect_correction(<<~RUBY)
      Cask::Caskroom.cask_installed?(cask_token)
    RUBY
  end

  it "registers an offense and corrects cask installed version checks" do
    expect_offense(<<~RUBY)
      Cask::Cask.new(name, config: config).installed_version
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Cask::Caskroom.cask_installed_version(name)` instead of `Cask::Cask.new(name, config: config).installed_version`.
    RUBY

    expect_correction(<<~RUBY)
      Cask::Caskroom.cask_installed_version(name)
    RUBY
  end

  it "does not register an offense for formula methods that require a formula instance" do
    expect_no_offenses(<<~RUBY)
      Formula["foo"].keg_only?
    RUBY
  end

  it "does not register an offense for dynamic formula installed checks that may need alias metadata" do
    expect_no_offenses(<<~RUBY)
      Formula[dependency].any_version_installed?
    RUBY
  end

  it "does not register an offense for cask loader methods that may need DSL metadata" do
    expect_no_offenses(<<~RUBY)
      Cask::CaskLoader.load(cask_token).installed?
    RUBY
  end

  it "does not register an offense when `Formula[]` is used for error handling" do
    expect_no_offenses(<<~RUBY)
      begin
        Formula[dependency].any_version_installed?
      rescue FormulaUnavailableError
        false
      end
    RUBY
  end

  it "does not register an offense for scoped formula helpers outside service blocks" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        on_linux do
          Utils::Path.formula_any_version_installed?("glibc")
        end
      end
    RUBY
  end

  it "does not register an offense for formula path calls used for error handling" do
    expect_no_offenses(<<~RUBY)
      begin
        Formula["foo"].opt_bin/"foo"
      rescue FormulaUnavailableError
        nil
      end
    RUBY
  end

  it "does not register an offense for `Formulary.factory` with additional arguments" do
    expect_no_offenses(<<~RUBY)
      Formulary.factory("foo", spec: :stable).opt_prefix
    RUBY
  end
end
