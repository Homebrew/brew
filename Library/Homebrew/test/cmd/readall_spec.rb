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
        depends_on macos: :ventura
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

  describe "Readall.valid_ruby_syntax?" do
    it "returns true for valid Ruby files" do
      file = mktmpdir/"valid.rb"
      file.write "puts 1\n"

      success = T.let(false, T::Boolean)
      expect { success = Readall.valid_ruby_syntax?([file]) }.not_to output.to_stderr
      expect(success).to be true
    end

    it "prints errors for files with invalid syntax" do
      file = mktmpdir/"invalid.rb"
      file.write "def foo(\n"

      success = T.let(true, T::Boolean)
      expect { success = Readall.valid_ruby_syntax?([file]) }.to output(/syntax error/).to_stderr
      expect(success).to be false
    end

    it "prints warnings for files with questionable syntax" do
      file = mktmpdir/"warning.rb"
      file.write "def foo\n  bar = 1\n  nil\nend\n"

      success = T.let(true, T::Boolean)
      expect { success = Readall.valid_ruby_syntax?([file]) }.to output(/unused variable/).to_stderr
      expect(success).to be false
    end

    it "aggregates failures across parallel worker processes" do
      dir = mktmpdir
      files = (1..9).map do |i|
        file = dir/"valid#{i}.rb"
        file.write "puts #{i}\n"
        file
      end
      bad_file = dir/"invalid.rb"
      bad_file.write "def foo(\n"
      files << bad_file

      success = T.let(true, T::Boolean)
      expect { success = Readall.valid_ruby_syntax?(files) }.to output(/syntax error/).to_stderr
      expect(success).to be false
    end
  end

  it "validates tap files in parallel worker processes" do
    tap_path = mktmpdir
    cask_files = (1..8).map do |i|
      file = tap_path/"Casks/linux-example#{i}.rb"
      file.dirname.mkpath
      file.write <<~RUBY
        cask "linux-example#{i}" do
          version "1.0"
          sha256 arm: "0000000000000000000000000000000000000000000000000000000000000000"
          url "https://example.invalid/x.tar.gz"
          name "Example"
          desc "Cask missing Linux stanzas"
          homepage "https://example.invalid/"
          binary "x"
        end
      RUBY
      file
    end

    success = T.let(true, T::Boolean)
    expect do
      success = Homebrew::SimulateSystem.with(os: :linux) do
        Readall.valid_tap?(
          instance_double(Tap, formula_files: [], cask_files:),
          os_arch_combinations: [[:linux, :arm]],
        )
      end
    end.to output(a_string_matching(/(?=.*linux-example1\.rb)(?=.*linux-example8\.rb)/m)).to_stderr

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

  it "reports Linux architectures missing a checksum despite an `on_macos` macOS dependency" do
    tap_path = mktmpdir
    cross_os_cask_file = tap_path/"Casks/cross-os-example.rb"
    cross_os_cask_file.dirname.mkpath
    cross_os_cask_file.write <<~RUBY
      cask "cross-os-example" do
        version "1.0"
        sha256 arm:          "0000000000000000000000000000000000000000000000000000000000000000",
               intel:        "1111111111111111111111111111111111111111111111111111111111111111",
               x86_64_linux: "2222222222222222222222222222222222222222222222222222222222222222"
        url "https://example.invalid/x.tar.gz"
        name "Example"
        desc "Cross-OS cask"
        homepage "https://example.invalid/"

        on_macos do
          depends_on macos: :ventura
        end

        binary "x"
      end
    RUBY

    success = T.let(false, T::Boolean)
    expect do
      success = Homebrew::SimulateSystem.with(os: :linux) do
        Readall.valid_tap?(
          instance_double(Tap, formula_files: [], cask_files: [cross_os_cask_file]),
          os_arch_combinations: [[:linux, :arm]],
        )
      end
    end.to output(/Missing Linux stanzas/).to_stderr

    expect(success).to be false
  end

  it "allows Linux architectures excluded by `depends_on arch:`" do
    tap_path = mktmpdir
    linux_intel_cask_file = tap_path/"Casks/linux-intel-example.rb"
    linux_intel_cask_file.dirname.mkpath
    linux_intel_cask_file.write <<~RUBY
      cask "linux-intel-example" do
        version "1.0"
        sha256 arm:          "0000000000000000000000000000000000000000000000000000000000000000",
               intel:        "1111111111111111111111111111111111111111111111111111111111111111",
               x86_64_linux: "2222222222222222222222222222222222222222222222222222222222222222"
        url "https://example.invalid/x.tar.gz"
        name "Example"
        desc "Intel-only-on-Linux cask"
        homepage "https://example.invalid/"

        on_linux do
          depends_on arch: :x86_64
        end

        binary "x"
      end
    RUBY

    success = T.let(false, T::Boolean)
    expect do
      success = Homebrew::SimulateSystem.with(os: :linux) do
        Readall.valid_tap?(
          instance_double(Tap, formula_files: [], cask_files: [linux_intel_cask_file]),
          os_arch_combinations: [[:linux, :arm], [:linux, :intel]],
        )
      end
    end.not_to output.to_stderr

    expect(success).to be true
  end
end
