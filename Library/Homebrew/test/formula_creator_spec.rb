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

    tests.each do |description, test|
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
end
