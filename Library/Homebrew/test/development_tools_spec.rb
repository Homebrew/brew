# typed: strict
# frozen_string_literal: true

require "development_tools"
require "utils/curl"

RSpec.describe DevelopmentTools do
  sig { returns(T.class_of(DevelopmentTools)) }
  subject(:development_tools) { Class.new(described_class) }

  describe ".curl_substitution_required?" do
    before do
      allow(development_tools).to receive(:curl_handles_most_https_certificates?).and_return(false)
      stub_const("HOMEBREW_BREWED_CURL_PATH", mktmpdir/"curl")
      ENV["HOMEBREW_MINIMUM_CURL_VERSION"] = "7.41.0"
    end

    test_each([["7.40.0", true], ["7.41.0", false]]) do |version, required|
      it "requires substitution=#{required} when the selected curl is #{version}" do
        allow(Utils::Curl).to receive(:curl_version).and_return(Version.new(version))

        expect(development_tools.curl_substitution_required?).to eq(required)
      end
    end
  end

  describe ".llvm_clang_build_version" do
    it "deprecates the LLVM Clang probe" do
      allow(Formula).to receive(:[]).with("llvm").and_raise(FormulaUnavailableError.new("llvm"))

      expect { development_tools.llvm_clang_build_version }
        .to raise_error(MethodDeprecatedError, /DevelopmentTools\.llvm_clang_build_version.*--version/)
    end

    it "still returns the LLVM Clang version" do
      llvm_prefix = mktmpdir
      clang = llvm_prefix/"bin/clang"
      clang.dirname.mkpath
      clang.write "#!/bin/sh\n"
      clang.chmod 0755

      allow(development_tools).to receive(:odeprecated)
      allow(Formula).to receive(:[]).with("llvm")
                                    .and_return(instance_double(Formula, opt_prefix: llvm_prefix))
      allow(Utils).to receive(:popen_read_text)
        .with(clang, "--version", err: :err).and_return("clang version 21.1.0\n")

      expect(development_tools.llvm_clang_build_version).to eq(Version.new("21.1.0"))
    end

    it "still returns a null version when LLVM is unavailable" do
      allow(development_tools).to receive(:odeprecated)
      allow(Formula).to receive(:[]).with("llvm").and_raise(FormulaUnavailableError.new("llvm"))

      expect(development_tools.llvm_clang_build_version).to be_null
    end
  end

  describe ".clang_build_version" do
    it "uses the simulated macOS compiler build version" do
      require "os/mac/xcode"
      allow(Homebrew::SimulateSystem).to receive_messages(
        simulating?:                     true,
        simulating_or_running_on_macos?: true,
        current_os:                      :monterey,
        current_arch:                    :intel,
      )

      expect(development_tools.clang_build_version).to eq(Version.new("1400"))
    end
  end

  describe ".clear_version_cache" do
    sig { returns(Pathname) }
    let(:llvm_prefix) { mktmpdir }

    before do
      clang = llvm_prefix/"bin/clang"
      clang.dirname.mkpath
      clang.write "#!/bin/sh\n"
      clang.chmod 0755

      allow(Formula).to receive(:[]).with("llvm")
                                    .and_return(instance_double(Formula, opt_prefix: llvm_prefix))
      allow(Utils).to receive(:popen_read_text)
        .with(clang, "--version", err: :err).and_return("clang version 21.1.0\n")
    end

    it "refreshes the LLVM Clang version after an upgrade" do
      development_tools.llvm_clang_version
      allow(Utils).to receive(:popen_read_text)
        .with(llvm_prefix/"bin/clang", "--version", err: :err).and_return("clang version 22.1.0\n")

      development_tools.clear_version_cache

      expect(development_tools.llvm_clang_version).to eq(Version.new("22.1.0"))
    end

    it "detects LLVM Clang when the formula becomes available" do
      allow(Formula).to receive(:[]).with("llvm").and_raise(FormulaUnavailableError.new("llvm"))
      development_tools.llvm_clang_version
      allow(Formula).to receive(:[]).with("llvm")
                                    .and_return(instance_double(Formula, opt_prefix: llvm_prefix))

      development_tools.clear_version_cache

      expect(development_tools.llvm_clang_version).to eq(Version.new("21.1.0"))
    end

    it "forgets LLVM Clang when the formula becomes unavailable" do
      development_tools.llvm_clang_version
      allow(Formula).to receive(:[]).with("llvm").and_raise(FormulaUnavailableError.new("llvm"))

      development_tools.clear_version_cache

      expect(development_tools.llvm_clang_version).to be_null
    end
  end
end
