# typed: true
# frozen_string_literal: true

require "utils/cpan"
require "utils/curl"

RSpec.describe CPAN do
  let(:cpan_package_url) do
    "https://cpan.metacpan.org/authors/id/P/PE/PEVANS/Scalar-List-Utils-1.68.tar.gz"
  end
  let(:cpan_tgz_url) do
    "https://cpan.metacpan.org/authors/id/S/ST/STBEY/Example-Module-1.23.tgz"
  end
  let(:non_cpan_package_url) do
    "https://github.com/example/package/archive/v1.0.0.tar.gz"
  end

  def curl_result(stdout: "", success: true)
    status = instance_double(Process::Status, success?: success)
    instance_double(SystemCommand::Result, stdout:, status:)
  end

  describe CPAN::Package do
    let(:package_from_cpan_url) { described_class.new("Scalar::Util", cpan_package_url) }
    let(:package_from_tgz_url) { described_class.new("Example::Module", cpan_tgz_url) }
    let(:package_from_non_cpan_url) { described_class.new("SomePackage", non_cpan_package_url) }

    describe "initialize" do
      specify do
        expect(package_from_cpan_url.name).to eq "Scalar::Util"
        expect(package_from_cpan_url.current_version).to eq "1.68"
        expect(package_from_tgz_url.current_version).to eq "1.23"
      end
    end

    describe ".current_version" do
      it "returns nil for non-CPAN and unversioned archive URLs" do
        unversioned_package = described_class.new(
          "Example::Module",
          "https://cpan.metacpan.org/authors/id/E/EX/EXAMPLE/Example-Module-main.tar.gz",
        )

        expect([package_from_non_cpan_url.current_version, unversioned_package.current_version]).to eq([nil, nil])
      end
    end

    describe ".valid_cpan_package?" do
      specify do
        expect(package_from_cpan_url.valid_cpan_package?).to be true
        expect(package_from_non_cpan_url.valid_cpan_package?).to be false
      end
    end

    describe ".latest_cpan_info" do
      let(:latest_package_url) do
        "https://cpan.metacpan.org/authors/id/P/PE/PEVANS/Scalar-List-Utils-1.69.tar.gz"
      end
      let(:latest_metadata) do
        JSON.generate(
          "download_url"    => latest_package_url,
          "checksum_sha256" => "a" * 64,
          "version"         => "1.69",
        )
      end

      it "returns and caches release metadata" do
        expect(Utils::Curl).to receive(:curl_output)
          .with("https://fastapi.metacpan.org/v1/download_url/Scalar::Util", "--location", "--fail")
          .once
          .and_return(curl_result(stdout: latest_metadata))
        expected = ["Scalar::Util", latest_package_url, "a" * 64, "1.69"]

        expect([package_from_cpan_url.latest_cpan_info, package_from_cpan_url.latest_cpan_info])
          .to eq([expected, expected])
      end

      it "does not query MetaCPAN for non-CPAN resources" do
        expect(Utils::Curl).not_to receive(:curl_output)

        expect(package_from_non_cpan_url.latest_cpan_info).to be_nil
      end

      it "returns nil when MetaCPAN cannot be reached" do
        allow(Utils::Curl).to receive(:curl_output).and_return(curl_result(success: false))

        expect(package_from_cpan_url.latest_cpan_info).to be_nil
      end

      it "returns nil for invalid JSON" do
        allow(Utils::Curl).to receive(:curl_output).and_return(curl_result(stdout: "not json"))

        expect(package_from_cpan_url.latest_cpan_info).to be_nil
      end

      it "returns nil when required release metadata is missing" do
        responses = [
          JSON.generate("checksum_sha256" => "a" * 64, "version" => "1.69"),
          JSON.generate("download_url" => latest_package_url, "version" => "1.69"),
        ].map { |stdout| curl_result(stdout:) }
        allow(Utils::Curl).to receive(:curl_output).and_return(*responses)
        packages = [
          described_class.new("Scalar::Util", cpan_package_url),
          described_class.new("Scalar::Util", cpan_package_url),
        ]

        expect(packages.map(&:latest_cpan_info)).to eq([nil, nil])
      end
    end

    describe ".to_s" do
      it "returns resource name" do
        expect(package_from_cpan_url.to_s).to eq "Scalar::Util"
      end
    end
  end

  describe ".update_perl_resources!" do
    let(:formula_path) { mktmpdir/"foo.rb" }
    let(:formula_contents) do
      <<~RUBY
        class Foo < Formula
          desc "Test formula"
          homepage "https://example.com"
          url "https://example.com/foo-1.0.tar.gz"
          sha256 "#{"b" * 64}"

          resource "Scalar::Util" do
            url "#{cpan_package_url}"
            sha256 "#{"c" * 64}"
          end

          def install
            bin.install "foo"
          end
        end
      RUBY
    end
    let(:mixed_formula_contents) do
      formula_contents.sub(
        "  def install",
        [
          '  resource "vendored-blob" do',
          "    url \"#{non_cpan_package_url}\"",
          "    sha256 \"#{"e" * 64}\"",
          "  end",
          "",
          "  def install",
        ].join("\n"),
      )
    end
    let(:livecheck_formula_contents) do
      formula_contents.sub(
        "    sha256 \"#{"c" * 64}\"",
        [
          "    sha256 \"#{"c" * 64}\"",
          "    livecheck do",
          "      regex(/Scalar-List-Utils[._-]v?\\d+(?:\\.\\d+)+\\.t/i)",
          "    end",
        ].join("\n"),
      )
    end
    let(:test_formula) do
      formula_path.write(formula_contents)
      resource_url = cpan_package_url
      formula("foo", path: formula_path) do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/foo-1.0.tar.gz"
        resource "Scalar::Util" do
          url resource_url
          sha256 "c" * 64
        end
      end
    end
    let(:mixed_formula) do
      formula_path.write(mixed_formula_contents)
      resource_url = cpan_package_url
      non_cpan_url = non_cpan_package_url
      formula("foo", path: formula_path) do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/foo-1.0.tar.gz"
        resource "Scalar::Util" do
          url resource_url
          sha256 "c" * 64
        end
        resource "vendored-blob" do
          url non_cpan_url
          sha256 "e" * 64
        end
      end
    end
    let(:livecheck_formula) do
      formula_path.write(livecheck_formula_contents)
      resource_url = cpan_package_url
      formula("foo", path: formula_path) do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/foo-1.0.tar.gz"
        resource "Scalar::Util" do
          url resource_url
          sha256 "c" * 64
          livecheck do
            regex(/Scalar-List-Utils[._-]v?\d+(?:\.\d+)+\.t/i)
          end
        end
      end
    end
    let(:latest_package_url) do
      "https://cpan.metacpan.org/authors/id/P/PE/PEVANS/Scalar-List-Utils-1.69.tar.gz"
    end
    let(:latest_metadata) do
      JSON.generate(
        "download_url"    => latest_package_url,
        "checksum_sha256" => "d" * 64,
        "version"         => "1.69",
      )
    end
    let(:updated_resource_output) do
      [
        "  resource \"Scalar::Util\" do",
        "    url \"#{latest_package_url}\"",
        "    sha256 \"#{"d" * 64}\"",
        "  end",
        "",
      ].join("\n")
    end

    before do
      allow(Utils::Curl).to receive(:curl_output).and_return(curl_result(stdout: latest_metadata))
    end

    it "prints updated CPAN resource blocks" do
      expect do
        described_class.update_perl_resources!(test_formula, print_only: true)
      end.to output(updated_resource_output).to_stdout
    end

    it "updates CPAN resource blocks in the formula" do
      described_class.update_perl_resources!(test_formula, quiet: true)

      expect(formula_path.read).to eq formula_contents.sub(cpan_package_url, latest_package_url)
                                                      .sub("c" * 64, "d" * 64)
    end

    it "fails without modifying formulas containing non-CPAN resources" do
      expect(Utils::Curl).not_to receive(:curl_output)

      expect do
        described_class.update_perl_resources!(mixed_formula, quiet: true)
      end.to raise_error(SystemExit).and output(
        /"foo" contains non-CPAN resources: vendored-blob.*Please update the resources manually/m,
      ).to_stderr
      expect(formula_path.read).to eq mixed_formula_contents
    end

    it "prints CPAN resource blocks for formulas containing non-CPAN resources" do
      expect do
        described_class.update_perl_resources!(mixed_formula, print_only: true)
      end.to output(updated_resource_output).to_stdout
    end

    it "fails without modifying formulas containing CPAN resource livecheck blocks" do
      expect(Utils::Curl).not_to receive(:curl_output)

      expect do
        described_class.update_perl_resources!(livecheck_formula, quiet: true)
      end.to raise_error(SystemExit).and output(
        /"foo" contains CPAN resources with livecheck blocks: Scalar::Util.*Please update the resources manually/m,
      ).to_stderr
      expect(formula_path.read).to eq livecheck_formula_contents
    end

    it "prints CPAN resource blocks for formulas containing CPAN resource livecheck blocks" do
      expect do
        described_class.update_perl_resources!(livecheck_formula, print_only: true)
      end.to output(updated_resource_output).to_stdout
    end

    it "reports resolved resource updates" do
      expect do
        described_class.update_perl_resources!(test_formula)
      end.to output(
        /Found 1 CPAN resources.*1\.68 -> 1\.69.*Updated 1 CPAN resource/m,
      ).to_stdout
    end

    it "reports resources that are already current" do
      current_metadata = JSON.generate(
        "download_url"    => cpan_package_url,
        "checksum_sha256" => "c" * 64,
        "version"         => "1.68",
      )
      allow(Utils::Curl).to receive(:curl_output).and_return(curl_result(stdout: current_metadata))

      expect do
        described_class.update_perl_resources!(test_formula)
      end.to output(/"Scalar::Util": already up to date \(1\.68\)/).to_stdout
    end

    it "fails when the formula has no CPAN resources" do
      non_cpan_url = non_cpan_package_url
      test_formula = formula("foo") do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/foo-1.0.tar.gz"
        resource "Example" do
          url non_cpan_url
          sha256 "e" * 64
        end
      end

      expect do
        described_class.update_perl_resources!(test_formula)
      end.to raise_error(SystemExit).and output(/"foo" has no CPAN resources to update/).to_stderr
    end

    it "fails when release metadata cannot be resolved" do
      allow(Utils::Curl).to receive(:curl_output).and_return(curl_result(success: false))

      expect do
        described_class.update_perl_resources!(test_formula, print_only: true)
      end.to raise_error(SystemExit).and output(/Unable to resolve "Scalar::Util"/).to_stderr
    end

    it "emits an error comment when unresolved resources are ignored" do
      allow(Utils::Curl).to receive(:curl_output).and_return(curl_result(success: false))

      expect do
        described_class.update_perl_resources!(test_formula, print_only: true, ignore_errors: true)
      end.to output("  # RESOURCE-ERROR: Unable to resolve \"Scalar::Util\"\n").to_stdout
    end

    it "writes error comments and marks the command failed when unresolved resources are ignored" do
      allow(Utils::Curl).to receive(:curl_output).and_return(curl_result(success: false))
      test_formula
      Homebrew.failed = false

      expect do
        described_class.update_perl_resources!(test_formula, ignore_errors: true, quiet: true)
      end.to output(/Unable to resolve some dependencies/).to_stderr
      expect([formula_path.read.include?('  # RESOURCE-ERROR: Unable to resolve "Scalar::Util"'), Homebrew.failed?])
        .to eq([true, true])
    end
  end
end
