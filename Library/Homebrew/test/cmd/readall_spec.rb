# typed: strict
# frozen_string_literal: true

require "cmd/readall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::ReadallCmd do
  it_behaves_like "parseable arguments"

  it "imports all Formulae for a given Tap", :integration_test do
    formula_file = setup_test_formula "testball"

    alias_file = CoreTap.instance.alias_dir/"foobar"
    alias_file.parent.mkpath

    FileUtils.ln_s formula_file, alias_file

    expect { brew "readall", "--aliases", "--syntax", CoreTap.instance.name }
      .to be_a_success
      .and not_to_output.to_stdout
      .and not_to_output.to_stderr
  end

  it "skips macOS-only casks when loading tap casks on Linux" do
    tap_path = mktmpdir
    macos_only_cask_file = tap_path/"Casks/macos-only-example.rb"
    linux_cask_file = tap_path/"Casks/linux-example.rb"
    macos_only_cask_file.dirname.mkpath
    macos_only_cask_file.write <<~RUBY
      cask "macos-only-example" do
        version "1.0"
        sha256 arm:   "0000000000000000000000000000000000000000000000000000000000000000",
               intel: "1111111111111111111111111111111111111111111111111111111111111111"
        url "https://example.invalid/x.pkg"
        name "Example"
        desc "macOS-only cask"
        homepage "https://example.invalid/"
        depends_on macos: ">= :ventura"
        binary "x"
      end
    RUBY
    linux_cask_file.write <<~RUBY
      cask "linux-example" do
        version "1.0"
        sha256 arm:   "0000000000000000000000000000000000000000000000000000000000000000",
               intel: "1111111111111111111111111111111111111111111111111111111111111111"
        url "https://example.invalid/x.tar.gz"
        name "Example"
        desc "Linux-supported cask"
        homepage "https://example.invalid/"
        binary "x"
      end
    RUBY

    success = T.let(false, T::Boolean)
    expect do
      success = Homebrew::SimulateSystem.with(os: :linux) do
        Readall.valid_tap?(
          instance_double(Tap, formula_files: [], cask_files: [macos_only_cask_file, linux_cask_file]),
          os_arch_combinations: [[:linux, :arm]],
        )
      end
    end.to output(a_string_matching(/\A(?=.*linux-example)(?!.*macos-only-example).*\z/m)).to_stderr

    expect(success).to be false
  end

  it "explains nil sha256 values when loading tap casks on Linux" do
    tap_path = mktmpdir
    linux_cask_file = tap_path/"Casks/linux-example.rb"
    linux_cask_file.dirname.mkpath
    linux_cask_file.write <<~RUBY
      cask "linux-example" do
        version "1.0"
        sha256 arm: "0000000000000000000000000000000000000000000000000000000000000000"
        url "https://example.invalid/x.tar.gz"
        name "Example"
        desc "Linux-supported cask"
        homepage "https://example.invalid/"
        binary "x"
      end
    RUBY

    success = T.let(false, T::Boolean)
    expect do
      success = Homebrew::SimulateSystem.with(os: :linux) do
        Readall.valid_tap?(
          instance_double(Tap, formula_files: [], cask_files: [linux_cask_file]),
          os_arch_combinations: [[:linux, :arm]],
        )
      end
    end.to output(/Missing Linux stanzas.*`depends_on :macos`/m).to_stderr

    expect(success).to be false
  end
end
