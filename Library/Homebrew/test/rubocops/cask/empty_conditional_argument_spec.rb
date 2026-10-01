# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::EmptyConditionalArgument, :config do
  it "reports an offense when a trailing argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: ""
                            ^^^^^^^^^ Remove the empty `intel:` argument from the `arch` stanza.
        file_arch = on_arch_conditional arm: "-aarch64", intel: ""
                                                         ^^^^^^^^^ Remove the empty `intel:` argument from the `on_arch_conditional` stanza.
        os macos: "-darwin", linux: ""
                             ^^^^^^^^^ Remove the empty `linux:` argument from the `os` stanza.
        file_os on_system_conditional macos: "-mac", linux: ""
                                                     ^^^^^^^^^ Remove the empty `linux:` argument from the `on_system_conditional` stanza.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64"
        file_arch = on_arch_conditional arm: "-aarch64"
        os macos: "-darwin"
        file_os on_system_conditional macos: "-mac"
      end
    CASK
  end

  it "reports an offense when a leading argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "", intel: "-intel"
             ^^^^^^^ Remove the empty `arm:` argument from the `arch` stanza.
        file_arch = on_arch_conditional arm: "", intel: "-x86_64"
                                        ^^^^^^^ Remove the empty `arm:` argument from the `on_arch_conditional` stanza.
        os macos: "", linux: "-linux"
           ^^^^^^^^^ Remove the empty `macos:` argument from the `os` stanza.
        file_os on_system_conditional macos: "", linux: "-gnu"
                                      ^^^^^^^^^ Remove the empty `macos:` argument from the `on_system_conditional` stanza.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch intel: "-intel"
        file_arch = on_arch_conditional intel: "-x86_64"
        os linux: "-linux"
        file_os on_system_conditional linux: "-gnu"
      end
    CASK
  end

  it "reports an offense when a nested argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(macos: "-intel", linux: "")
                                                                          ^^^^^^^^^ Remove the empty `linux:` argument from the `on_system_conditional` stanza.
        os macos: on_arch_conditional(arm: "", intel: "-mac"), linux: "-linux"
                                      ^^^^^^^ Remove the empty `arm:` argument from the `on_arch_conditional` stanza.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(macos: "-intel")
        os macos: on_arch_conditional(intel: "-mac"), linux: "-linux"
      end
    CASK
  end

  it "reports an offense when every argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "", intel: ""
        ^^^^^^^^^^^^^^^^^^^^^^^ Remove the `arch` stanza as all its arguments are empty.
        file_arch = on_arch_conditional arm: "", intel: ""
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the `on_arch_conditional` stanza as all its arguments are empty.
        os macos: "", linux: ""
        ^^^^^^^^^^^^^^^^^^^^^^^ Remove the `os` stanza as all its arguments are empty.
        file_os = on_system_conditional macos: "", linux: ""
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the `on_system_conditional` stanza as all its arguments are empty.
        url "https://example.com/foo.zip"
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"
      end
    CASK
  end

  it "reports an offense when every nested argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(macos: "", linux: "")
                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the `on_system_conditional` stanza as all its arguments are empty.
        os macos: on_arch_conditional(arm: "", intel: ""), linux: "-linux"
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the `on_arch_conditional` stanza as all its arguments are empty.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64"
        os linux: "-linux"
      end
    CASK
  end

  it "reports an offense when the only argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: ""
        ^^^^^^^^^^^^ Remove the `arch` stanza as all its arguments are empty.
        file_arch = on_arch_conditional intel: ""
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the `on_arch_conditional` stanza as all its arguments are empty.
        os macos: ""
        ^^^^^^^^^^^^ Remove the `os` stanza as all its arguments are empty.
        file_os = on_system_conditional linux: ""
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the `on_system_conditional` stanza as all its arguments are empty.
        url "https://example.com/foo.zip"
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"
      end
    CASK
  end

  it "reports an offense when the only nested argument is an empty string" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(macos: "")
                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the `on_system_conditional` stanza as all its arguments are empty.
        os macos: on_arch_conditional(intel: ""), linux: "-linux"
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the `on_arch_conditional` stanza as all its arguments are empty.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64"
        os linux: "-linux"
      end
    CASK
  end

  it "reports an offense without crashing when an argument key is not a literal" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", some_method => ""
                            ^^^^^^^^^^^^^^^^^ Remove the empty `some_method:` argument from the `arch` stanza.
        file_arch = on_arch_conditional intel: "-x86_64", some_method => ""
                                                          ^^^^^^^^^^^^^^^^^ Remove the empty `some_method:` argument from the `on_arch_conditional` stanza.
        os macos: "-darwin", some_method => ""
                             ^^^^^^^^^^^^^^^^^ Remove the empty `some_method:` argument from the `os` stanza.
        file_os = on_system_conditional linux: "-gnu", some_method => ""
                                                       ^^^^^^^^^^^^^^^^^ Remove the empty `some_method:` argument from the `on_system_conditional` stanza.
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64"
        file_arch = on_arch_conditional intel: "-x86_64"
        os macos: "-darwin"
        file_os = on_system_conditional linux: "-gnu"
      end
    CASK
  end

  it "reports no offenses when no argument is an empty string" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: "-intel"
        file_arch = on_arch_conditional arm: "-aarch64", intel: "-x86_64"
        os macos: "-darwin", linux: "-linux"
        file_os = on_system_conditional macos: "-mac", linux: "-gnu"
      end
    CASK
  end

  it "reports no offenses when no nested argument is an empty string" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(macos: "-intel", linux: "-x86_64")
        os macos: on_arch_conditional(arm: "-darwin", intel: "-mac"), linux: "-linux"
      end
    CASK
  end
end
