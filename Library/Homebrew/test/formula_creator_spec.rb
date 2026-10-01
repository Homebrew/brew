# typed: strict
# frozen_string_literal: true

require "formula_creator"

RSpec.describe Homebrew::FormulaCreator do
  describe ".new" do
    tests = {
      "generic tarball URL":             {
        url:              "http://digit-labs.org/files/tools/synscan/releases/synscan-5.02.tar.gz",
        expected_name:    "synscan",
        expected_version: "5.02",
      },
      "gitweb URL":                      {
        url:           "http://www.codesrc.com/gitweb/index.cgi?p=libzipper.git;a=summary",
        expected_name: "libzipper",
      },
      "GitHub repository URL with .git": {
        url:                    "https://github.com/Homebrew/brew.git",
        fetch:                  true,
        github_user_repository: ["Homebrew", "brew"],
        expected_name:          "brew",
        expected_head:          true,
      },
      "GitHub archive URL":              {
        url:                    "https://github.com/Homebrew/brew/archive/4.5.7.tar.gz",
        fetch:                  true,
        github_user_repository: ["Homebrew", "brew"],
        expected_name:          "brew",
        expected_version:       "4.5.7",
      },
      "GitHub releases URL":             {
        url:                    "https://github.com/stella-emu/stella/releases/download/6.7/stella-6.7-src.tar.xz",
        fetch:                  true,
        github_user_repository: ["stella-emu", "stella"],
        expected_name:          "stella",
        expected_version:       "6.7",
      },
      "GitHub latest release":           {
        url:                    "https://github.com/buildpacks/pack",
        fetch:                  true,
        github_user_repository: ["buildpacks", "pack"],
        latest_release:         { "tag_name" => "v0.37.0" },
        expected_name:          "pack",
        expected_url:           "https://github.com/buildpacks/pack/archive/refs/tags/v0.37.0.tar.gz",
        expected_version:       "v0.37.0",
      },
      "GitHub URL with name override":   {
        url:           "https://github.com/RooVetGit/Roo-Code",
        name:          "roo",
        expected_name: "roo",
      },
    }

    test_each(tests) do |(description, test)|
      it "parses #{description}" do
        fetch = test.fetch(:fetch, false)
        if fetch
          github_user_repository = test.fetch(:github_user_repository)
          allow(GitHub).to receive(:repository).with(*github_user_repository)
          if (latest_release = test[:latest_release])
            expect(GitHub).to receive(:get_latest_release).with(*github_user_repository).and_return(latest_release)
          end
        end

        formula_creator = described_class.new(url: test.fetch(:url), name: test[:name], fetch:)

        expect(formula_creator.name).to eq(test.fetch(:expected_name))
        if (expected_version = test[:expected_version])
          expect(formula_creator.version).to eq(expected_version)
        else
          expect(formula_creator.version).to be_null
        end
        if (expected_url = test[:expected_url])
          expect(formula_creator.url).to eq(expected_url)
        end
        expect(formula_creator.head).to eq(test.fetch(:expected_head, false))
      end
    end
  end

  describe "#write_formula!" do
    it "writes upstream metadata as literal Ruby strings" do
      allow(GitHub).to receive(:repository).with("example", "foo").and_return(
        "description" => 'A "quoted" description <%# metadata %>',
        "homepage"    => 'https://example.com/a"b',
        "license"     => { "spdx_id" => 'License "example"' },
      )
      formula = described_class.new(url: "https://github.com/example/foo.git", version: "1", fetch: true)

      expect(formula.write_formula!.read).to include(
        %Q(desc #{'A "quoted" description <%# metadata %>'.inspect}),
        %Q(homepage #{'https://example.com/a"b'.inspect}),
        %Q(license #{'License "example"'.inspect}),
      )
    end

    shared_examples "expected" do |mode, includes:, excludes:|
      sig { returns(Pathname) }
      subject(:formula) do
        described_class.new(url: "https://brew.sh/foo-0.1.tgz", mode:).write_formula!
      end

      it "writes a formula with valid syntax when using #{mode} template" do
        expect { Formulary.factory(formula) }.not_to raise_error
      end

      specify "when using #{mode} template" do
        expect(formula).to be_a_file
        contents = formula.read
        expect(contents).to include(*includes)
        expect(contents).not_to include(*excludes)
      end
    end

    it_behaves_like "expected", :autotools,
                    includes: ["deny_network_access!", "std_configure_args", "unrecognized options"],
                    excludes: ['resource "']

    it_behaves_like "expected", :cabal,
                    includes: ["deny_network_access!", "std_cabal_v2_args", /"cabal".*"--only-download"/],
                    excludes: ["unrecognized options", 'resource "']

    it_behaves_like "expected", :cmake,
                    includes: ["deny_network_access!", "std_cmake_args"],
                    excludes: ["unrecognized options", 'resource "']

    it_behaves_like "expected", :crystal,
                    includes: ["deny_network_access!",
                               '"shards", "install", "--production", "--skip-postinstall"',
                               '"shards", "build", *std_shards_args'],
                    excludes: ["unrecognized options", 'resource "']

    it_behaves_like "expected", :go,
                    includes: ["deny_network_access!", "std_go_args", /"go".*"download"/],
                    excludes: ["unrecognized options", 'resource "']

    it_behaves_like "expected", :meson,
                    includes: ["deny_network_access!", "std_meson_args"],
                    excludes: ["unrecognized options", 'resource "']

    it_behaves_like "expected", :perl,
                    includes: ["deny_network_access!", "PERL5LIB", 'resource "'],
                    excludes: ["unrecognized options"]

    it_behaves_like "expected", :ruby,
                    includes: ["deny_network_access!", /"cache".*"--no-install"/, /"install".*"--local"/],
                    excludes: ["unrecognized options", 'resource "']

    it_behaves_like "expected", :rust,
                    includes: ["deny_network_access!",
                               '"cargo", "install", *std_cargo_args',
                               '"cargo", "fetch", *std_cargo_fetch_args'],
                    excludes: ["unrecognized options", 'resource "']

    it_behaves_like "expected", :zig,
                    includes: ["deny_network_access!", "std_zig_args", "--fetch"],
                    excludes: ["unrecognized options", 'resource "']

    it_behaves_like "expected", nil,
                    includes: ["deny_network_access!", "unrecognized options"],
                    excludes: ['resource "']
  end
end
