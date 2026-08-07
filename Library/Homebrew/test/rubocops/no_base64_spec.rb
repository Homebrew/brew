# typed: strict
# frozen_string_literal: true

require "rubocops/no_base64"

RSpec.describe RuboCop::Cop::Homebrew::NoBase64, :config do
  it "registers an offense and removes `require \"base64\"`" do
    expect_offense(<<~RUBY)
      require "base64"
      ^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
      require "json"
    RUBY

    expect_correction(<<~RUBY)
      require "json"
    RUBY
  end

  it "registers an offense and removes `Kernel.require \"base64\"`" do
    expect_offense(<<~RUBY)
      Kernel.require "base64"
      ^^^^^^^^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
      require "json"
    RUBY

    expect_correction(<<~RUBY)
      require "json"
    RUBY
  end

  it "registers an offense and corrects `Base64.decode64`" do
    expect_offense(<<~RUBY)
      Base64.decode64(foo)
      ^^^^^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
    RUBY

    expect_correction(<<~RUBY)
      foo.unpack1("m")
    RUBY
  end

  it "registers an offense and corrects `Base64.strict_decode64`" do
    expect_offense(<<~RUBY)
      Base64.strict_decode64("aGVsbG8=")
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
    RUBY

    expect_correction(<<~RUBY)
      "aGVsbG8=".unpack1("m0")
    RUBY
  end

  it "registers an offense and corrects `Base64.encode64`" do
    expect_offense(<<~RUBY)
      Base64.encode64(file.read)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
    RUBY

    expect_correction(<<~RUBY)
      [file.read].pack("m")
    RUBY
  end

  it "registers an offense and corrects `Base64.strict_encode64`" do
    expect_offense(<<~RUBY)
      Base64.strict_encode64("hello" * count)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
    RUBY

    expect_correction(<<~RUBY)
      ["hello" * count].pack("m0")
    RUBY
  end

  it "registers an offense and corrects `::Base64` calls" do
    expect_offense(<<~RUBY)
      ::Base64.decode64(foo)
      ^^^^^^^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
    RUBY

    expect_correction(<<~RUBY)
      foo.unpack1("m")
    RUBY
  end

  it "registers an offense without correction for other `Base64` methods" do
    expect_offense(<<~RUBY)
      Base64.urlsafe_decode64(foo)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
    RUBY

    expect_no_corrections
  end

  it "registers an offense without correction for a decode of a compound expression" do
    expect_offense(<<~RUBY)
      Base64.decode64(foo + bar)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
    RUBY

    expect_no_corrections
  end

  it "registers an offense without correction for a bare `Base64` reference" do
    expect_offense(<<~RUBY)
      encoder = Base64
                ^^^^^^ Homebrew no longer includes the `base64` gem; use `String#unpack1` or `Array#pack` instead.
    RUBY

    expect_no_corrections
  end

  it "does not register an offense for a formula class named `Base64`" do
    expect_no_offenses(<<~RUBY)
      class Base64 < Formula
        desc "Encode and decode base64 files"
      end
    RUBY
  end

  it "does not register an offense for namespaced `Base64` constants" do
    expect_no_offenses(<<~RUBY)
      Foo::Base64.decode64(foo)
    RUBY
  end

  it "does not register an offense for other requires" do
    expect_no_offenses(<<~RUBY)
      require "json"
    RUBY
  end
end
