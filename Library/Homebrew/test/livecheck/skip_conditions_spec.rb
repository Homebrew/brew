# frozen_string_literal: true

require "livecheck/livecheck"
require "livecheck/skip_conditions"

RSpec.describe Homebrew::Livecheck::SkipConditions do
  subject(:skip_conditions) { described_class }

  let(:formulae) do
    {
      basic:               formula("test") do
        desc "Test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"
        head "https://github.com/Homebrew/brew.git"

        livecheck do
          url "https://formulae.brew.sh/api/formula/ruby.json"
          regex(/"stable":"(\d+(?:\.\d+)+)"/i)
        end
      end,
      deprecated:          formula("test_deprecated") do
        desc "Deprecated test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"
        deprecate! date: "2020-06-25", because: :unmaintained
      end,
      disabled:            formula("test_disabled") do
        desc "Disabled test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"
        disable! date: "2020-06-25", because: :unmaintained
      end,
      head_only:           formula("test_head_only") do
        desc "HEAD-only test formula"
        homepage "https://brew.sh"
        head "https://github.com/Homebrew/brew.git"
      end,
      gist:                formula("test_gist") do
        desc "Gist test formula"
        homepage "https://brew.sh"
        url "https://gist.github.com/Homebrew/0000000000"
      end,
      google_code_archive: formula("test_google_code_archive") do
        desc "Google Code Archive test formula"
        homepage "https://brew.sh"
        url "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/brew/brew-1.0.0.tar.gz"
      end,
      internet_archive:    formula("test_internet_archive") do
        desc "Internet Archive test formula"
        homepage "https://brew.sh"
        url "https://web.archive.org/web/20200101000000/https://brew.sh/test-0.0.1.tgz"
      end,
      skip:                formula("test_skip") do
        desc "Skipped test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"

        livecheck do
          skip
        end
      end,
      skip_with_message:   formula("test_skip_with_message") do
        desc "Skipped test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"

        livecheck do
          skip "Not maintained"
        end
      end,
      versioned:           formula("test@0.0.1") do
        desc "Versioned test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz"
      end,
    }
  end

  let(:casks) do
    {
      basic:             Cask::Cask.new("test") do
        version "0.0.1,2"

        url "https://brew.sh/test-0.0.1.tgz"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"

        livecheck do
          url "https://formulae.brew.sh/api/formula/ruby.json"
          regex(/"stable":"(\d+(?:\.\d+)+)"/i)
        end
      end,
      deprecated:        Cask::Cask.new("test_deprecated") do
        version "0.0.1"
        sha256 :no_check

        url "https://brew.sh/test-0.0.1.tgz"
        name "Test Deprecate"
        desc "Deprecated test cask"
        homepage "https://brew.sh"

        deprecate! date: "2020-06-25", because: :discontinued
      end,
      disabled:          Cask::Cask.new("test_disabled") do
        version "0.0.1"
        sha256 :no_check

        url "https://brew.sh/test-0.0.1.tgz"
        name "Test Disable"
        desc "Disabled test cask"
        homepage "https://brew.sh"

        disable! date: "2020-06-25", because: :discontinued
      end,
      extract_plist:     Cask::Cask.new("test_extract_plist_skip") do
        version "0.0.1"

        url "https://brew.sh/test-0.0.1.tgz"
        name "Test ExtractPlist Skip"
        desc "Skipped test cask"
        homepage "https://brew.sh"

        livecheck do
          strategy :extract_plist
        end
      end,
      latest:            Cask::Cask.new("test_latest") do
        version :latest
        sha256 :no_check

        url "https://brew.sh/test-0.0.1.tgz"
        name "Test Latest"
        desc "Latest test cask"
        homepage "https://brew.sh"
      end,
      unversioned:       Cask::Cask.new("test_unversioned") do
        version "1.2.3"
        sha256 :no_check

        url "https://brew.sh/test.tgz"
        name "Test Unversioned"
        desc "Unversioned test cask"
        homepage "https://brew.sh"
      end,
      skip:              Cask::Cask.new("test_skip") do
        version "0.0.1"

        url "https://brew.sh/test-0.0.1.tgz"
        name "Test Skip"
        desc "Skipped test cask"
        homepage "https://brew.sh"

        livecheck do
          skip
        end
      end,
      skip_with_message: Cask::Cask.new("test_skip_with_message") do
        version "0.0.1"

        url "https://brew.sh/test-0.0.1.tgz"
        name "Test Skip"
        desc "Skipped test cask"
        homepage "https://brew.sh"

        livecheck do
          skip "Not maintained"
        end
      end,
    }
  end

  let(:status_hashes) do
    {
      formula: {
        deprecated:          {
          formula: "test_deprecated",
          status:  "deprecated",
          meta:    {
            livecheck_defined: false,
          },
        },
        disabled:            {
          formula: "test_disabled",
          status:  "disabled",
          meta:    {
            livecheck_defined: false,
          },
        },
        versioned:           {
          formula: "test@0.0.1",
          status:  "versioned",
          meta:    {
            livecheck_defined: false,
          },
        },
        head_only:           {
          formula:  "test_head_only",
          status:   "error",
          messages: ["HEAD only formula must be installed to be checkable"],
          meta:     {
            livecheck_defined: false,
            head_only:         true,
          },
        },
        gist:                {
          formula:  "test_gist",
          status:   "skipped",
          messages: ["Stable URL is a GitHub Gist"],
          meta:     {
            livecheck_defined: false,
          },
        },
        google_code_archive: {
          formula:  "test_google_code_archive",
          status:   "skipped",
          messages: ["Stable URL is from Google Code Archive"],
          meta:     {
            livecheck_defined: false,
          },
        },
        internet_archive:    {
          formula:  "test_internet_archive",
          status:   "skipped",
          messages: ["Stable URL is from Internet Archive"],
          meta:     {
            livecheck_defined: false,
          },
        },
        skip:                {
          formula: "test_skip",
          status:  "skipped",
          meta:    {
            livecheck_defined: true,
          },
        },
        skip_with_message:   {
          formula:  "test_skip_with_message",
          status:   "skipped",
          messages: ["Not maintained"],
          meta:     {
            livecheck_defined: true,
          },
        },
      },
      cask:    {
        deprecated:        {
          cask:   "test_deprecated",
          status: "deprecated",
          meta:   {
            livecheck_defined: false,
          },
        },
        disabled:          {
          cask:   "test_disabled",
          status: "disabled",
          meta:   {
            livecheck_defined: false,
          },
        },
        extract_plist:     {
          cask:     "test_extract_plist_skip",
          status:   "skipped",
          messages: ["Use `--extract-plist` to enable checking multiple casks with ExtractPlist strategy"],
          meta:     {
            livecheck_defined: true,
          },
        },
        latest:            {
          cask:   "test_latest",
          status: "latest",
          meta:   {
            livecheck_defined: false,
          },
        },
        unversioned:       {
          cask:   "test_unversioned",
          status: "unversioned",
          meta:   {
            livecheck_defined: false,
          },
        },
        skip:              {
          cask:   "test_skip",
          status: "skipped",
          meta:   {
            livecheck_defined: true,
          },
        },
        skip_with_message: {
          cask:     "test_skip_with_message",
          status:   "skipped",
          messages: ["Not maintained"],
          meta:     {
            livecheck_defined: true,
          },
        },
      },
    }
  end

  describe "::skip_information" do
    context "when a formula without a `livecheck` block is deprecated" do
      it "skips" do
        expect(skip_conditions.skip_information(formulae[:deprecated]))
          .to eq(status_hashes[:formula][:deprecated])
      end
    end

    context "when a formula without a `livecheck` block is disabled" do
      it "skips" do
        expect(skip_conditions.skip_information(formulae[:disabled]))
          .to eq(status_hashes[:formula][:disabled])
      end
    end

    context "when a formula without a `livecheck` block is versioned" do
      it "skips" do
        expect(skip_conditions.skip_information(formulae[:versioned]))
          .to eq(status_hashes[:formula][:versioned])
      end
    end

    context "when a formula is HEAD-only and not installed" do
      it "skips" do
        expect(skip_conditions.skip_information(formulae[:head_only]))
          .to eq(status_hashes[:formula][:head_only])
      end
    end

    context "when a formula without a `livecheck` block has a GitHub Gist stable URL" do
      it "skips" do
        expect(skip_conditions.skip_information(formulae[:gist]))
          .to eq(status_hashes[:formula][:gist])
      end
    end

    context "when a formula without a `livecheck` block has a Google Code Archive stable URL" do
      it "skips" do
        expect(skip_conditions.skip_information(formulae[:google_code_archive]))
          .to eq(status_hashes[:formula][:google_code_archive])
      end
    end

    context "when a formula without a `livecheck` block has an Internet Archive stable URL" do
      it "skips" do
        expect(skip_conditions.skip_information(formulae[:internet_archive]))
          .to eq(status_hashes[:formula][:internet_archive])
      end
    end

    context "when a formula has a `livecheck` block containing `skip`" do
      it "skips" do
        expect(skip_conditions.skip_information(formulae[:skip]))
          .to eq(status_hashes[:formula][:skip])

        expect(skip_conditions.skip_information(formulae[:skip_with_message]))
          .to eq(status_hashes[:formula][:skip_with_message])
      end
    end

    context "when a cask without a `livecheck` block is deprecated" do
      it "skips" do
        expect(skip_conditions.skip_information(casks[:deprecated]))
          .to eq(status_hashes[:cask][:deprecated])
      end
    end

    context "when a cask without a `livecheck` block is disabled" do
      it "skips" do
        expect(skip_conditions.skip_information(casks[:disabled]))
          .to eq(status_hashes[:cask][:disabled])
      end
    end

    context "when a cask has a `livecheck` block using `ExtractPlist` and `--extract-plist` is not used" do
      it "skips" do
        expect(skip_conditions.skip_information(casks[:extract_plist], extract_plist: false))
          .to eq(status_hashes[:cask][:extract_plist])
      end
    end

    context "when a cask without a `livecheck` block has `version :latest`" do
      it "skips" do
        expect(skip_conditions.skip_information(casks[:latest]))
          .to eq(status_hashes[:cask][:latest])
      end
    end

    context "when a cask without a `livecheck` block has an unversioned URL" do
      it "skips" do
        expect(skip_conditions.skip_information(casks[:unversioned]))
          .to eq(status_hashes[:cask][:unversioned])
      end
    end

    context "when a cask has a `livecheck` block containing `skip`" do
      it "skips" do
        expect(skip_conditions.skip_information(casks[:skip]))
          .to eq(status_hashes[:cask][:skip])

        expect(skip_conditions.skip_information(casks[:skip_with_message]))
          .to eq(status_hashes[:cask][:skip_with_message])
      end
    end

    it "returns an empty hash for a non-skippable formula" do
      expect(skip_conditions.skip_information(formulae[:basic])).to eq({})
    end

    it "returns an empty hash for a non-skippable cask" do
      expect(skip_conditions.skip_information(casks[:basic])).to eq({})
    end
  end

  describe "::referenced_skip_information" do
    let(:original_name) { "original" }

    context "when a formula without a `livecheck` block is deprecated" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(formulae[:deprecated], original_name) }
          .to raise_error(RuntimeError, "Referenced formula (test_deprecated) is skipped as deprecated")
      end
    end

    context "when a formula without a `livecheck` block is disabled" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(formulae[:disabled], original_name) }
          .to raise_error(RuntimeError, "Referenced formula (test_disabled) is skipped as disabled")
      end
    end

    context "when a formula without a `livecheck` block is versioned" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(formulae[:versioned], original_name) }
          .to raise_error(RuntimeError, "Referenced formula (test@0.0.1) is skipped as versioned")
      end
    end

    context "when a formula is HEAD-only and not installed" do
      it "skips" do
        expect(skip_conditions.referenced_skip_information(formulae[:head_only], original_name))
          .to eq(status_hashes[:formula][:head_only].merge({ formula: original_name }))
      end
    end

    context "when a formula without a `livecheck` block has a GitHub Gist stable URL" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(formulae[:gist], original_name) }
          .to raise_error(RuntimeError, "Referenced formula (test_gist) is automatically skipped")
      end
    end

    context "when a formula without a `livecheck` block has a Google Code Archive stable URL" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(formulae[:google_code_archive], original_name) }
          .to raise_error(RuntimeError, "Referenced formula (test_google_code_archive) is automatically skipped")
      end
    end

    context "when a formula without a `livecheck` block has an Internet Archive stable URL" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(formulae[:internet_archive], original_name) }
          .to raise_error(RuntimeError, "Referenced formula (test_internet_archive) is automatically skipped")
      end
    end

    context "when a formula has a `livecheck` block containing `skip`" do
      it "skips" do
        expect(skip_conditions.referenced_skip_information(formulae[:skip], original_name))
          .to eq(status_hashes[:formula][:skip].merge({ formula: original_name }))

        expect(skip_conditions.referenced_skip_information(formulae[:skip_with_message], original_name))
          .to eq(status_hashes[:formula][:skip_with_message].merge({ formula: original_name }))
      end
    end

    context "when a cask without a `livecheck` block is deprecated" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(casks[:deprecated], original_name) }
          .to raise_error(RuntimeError, "Referenced cask (test_deprecated) is skipped as deprecated")
      end
    end

    context "when a cask without a `livecheck` block is disabled" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(casks[:disabled], original_name) }
          .to raise_error(RuntimeError, "Referenced cask (test_disabled) is skipped as disabled")
      end
    end

    context "when a cask has a `livecheck` block using `ExtractPlist` and `--extract-plist` is not used" do
      it "skips" do
        expect do
          skip_conditions.referenced_skip_information(casks[:extract_plist], original_name, extract_plist: false)
        end
          .to raise_error(RuntimeError, "Referenced cask (test_extract_plist_skip) is automatically skipped")
      end
    end

    context "when a cask without a `livecheck` block has `version :latest`" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(casks[:latest], original_name) }
          .to raise_error(RuntimeError, "Referenced cask (test_latest) is skipped as latest")
      end
    end

    context "when a cask without a `livecheck` block has an unversioned URL" do
      it "errors" do
        expect { skip_conditions.referenced_skip_information(casks[:unversioned], original_name) }
          .to raise_error(RuntimeError, "Referenced cask (test_unversioned) is skipped as unversioned")
      end
    end

    context "when a cask has a `livecheck` block containing `skip`" do
      it "skips" do
        expect(skip_conditions.referenced_skip_information(casks[:skip], original_name))
          .to eq(status_hashes[:cask][:skip].merge({ cask: original_name }))

        expect(skip_conditions.referenced_skip_information(casks[:skip_with_message], original_name))
          .to eq(status_hashes[:cask][:skip_with_message].merge({ cask: original_name }))
      end
    end

    it "returns an empty hash for a non-skippable formula" do
      expect(skip_conditions.referenced_skip_information(formulae[:basic], original_name)).to be_nil
    end

    it "returns an empty hash for a non-skippable cask" do
      expect(skip_conditions.referenced_skip_information(casks[:basic], original_name)).to be_nil
    end
  end

  describe "::print_skip_information" do
    context "when a formula without a `livecheck` block is deprecated" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:formula][:deprecated]) }
          .to output("test_deprecated: deprecated\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when a formula without a `livecheck` block is disabled" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:formula][:disabled]) }
          .to output("test_disabled: disabled\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when a formula without a `livecheck` block is versioned" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:formula][:versioned]) }
          .to output("test@0.0.1: versioned\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when a formula is HEAD-only and not installed" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:formula][:head_only]) }
          .to output("test_head_only: HEAD only formula must be installed to be checkable\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when a formula has a GitHub Gist stable URL" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:formula][:gist]) }
          .to output("test_gist: skipped - Stable URL is a GitHub Gist\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when a formula has a Google Code Archive stable URL" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:formula][:google_code_archive]) }
          .to output("test_google_code_archive: skipped - Stable URL is from Google Code Archive\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when a formula has an Internet Archive stable URL" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:formula][:internet_archive]) }
          .to output("test_internet_archive: skipped - Stable URL is from Internet Archive\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when a formula has a `livecheck` block containing `skip`" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:formula][:skip]) }
          .to output("test_skip: skipped\n").to_stdout
          .and not_to_output.to_stderr

        expect { skip_conditions.print_skip_information(status_hashes[:formula][:skip_with_message]) }
          .to output("test_skip_with_message: skipped - Not maintained\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when the cask is deprecated without a `livecheck` block" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:cask][:deprecated]) }
          .to output("test_deprecated: deprecated\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when the cask is disabled without a `livecheck` block" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:cask][:disabled]) }
          .to output("test_disabled: disabled\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when the cask has `version :latest` without a `livecheck` block" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:cask][:latest]) }
          .to output("test_latest: latest\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when the cask has an unversioned URL without a `livecheck` block" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:cask][:unversioned]) }
          .to output("test_unversioned: unversioned\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "when the cask has a `livecheck` block containing `skip`" do
      it "prints skip information" do
        expect { skip_conditions.print_skip_information(status_hashes[:cask][:skip]) }
          .to output("test_skip: skipped\n").to_stdout
          .and not_to_output.to_stderr

        expect { skip_conditions.print_skip_information(status_hashes[:cask][:skip_with_message]) }
          .to output("test_skip_with_message: skipped - Not maintained\n").to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "with a blank parameter" do
      it "prints nothing" do
        expect { skip_conditions.print_skip_information({}) }
          .to not_to_output.to_stdout
          .and not_to_output.to_stderr
      end
    end
  end
end
