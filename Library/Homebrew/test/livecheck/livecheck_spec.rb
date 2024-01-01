# frozen_string_literal: true

require "livecheck/livecheck"

describe Homebrew::Livecheck do
  subject(:livecheck) { described_class }

  let(:cask_url) { "https://brew.sh/test-0.0.1.dmg" }
  let(:head_url) { "https://github.com/Homebrew/brew.git" }
  let(:homepage_url) { "https://brew.sh" }
  let(:livecheck_url) { "https://formulae.brew.sh/api/formula/ruby.json" }
  let(:stable_url) { "https://brew.sh/test-0.0.1.tgz" }
  let(:resource_url) { "https://brew.sh/foo-1.0.tar.gz" }

  let(:f) do
    formula("test") do
      desc "Test formula"
      homepage "https://brew.sh"
      url "https://brew.sh/test-0.0.1.tgz"
      head "https://github.com/Homebrew/brew.git"

      livecheck do
        url "https://formulae.brew.sh/api/formula/ruby.json"
        regex(/"stable":"(\d+(?:\.\d+)+)"/i)
      end

      resource "foo" do
        url "https://brew.sh/foo-1.0.tar.gz"
        sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

        livecheck do
          url "https://brew.sh/test/releases"
          regex(/foo[._-]v?(\d+(?:\.\d+)+)\.t/i)
        end
      end
    end
  end

  let(:r) { f.resources.first }

  let(:c) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "test" do
        version "0.0.1,2"

        url "https://brew.sh/test-0.0.1.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"

        livecheck do
          url "https://formulae.brew.sh/api/formula/ruby.json"
          regex(/"stable":"(\d+(?:.\d+)+)"/i)
        end
      end
    RUBY
  end

  describe "::resolve_livecheck_reference" do
    context "when a formula/cask has a livecheck block without formula/cask methods" do
      it "returns [nil, []]" do
        expect(livecheck.resolve_livecheck_reference(f)).to eq([nil, []])
        expect(livecheck.resolve_livecheck_reference(c)).to eq([nil, []])
      end
    end
  end

  describe "::formula_name" do
    it "returns the name of the formula" do
      expect(livecheck.formula_name(f)).to eq("test")
    end

    it "returns the full name" do
      expect(livecheck.formula_name(f, full_name: true)).to eq("test")
    end
  end

  describe "::cask_name" do
    it "returns the token of the cask" do
      expect(livecheck.cask_name(c)).to eq("test")
    end

    it "returns the full name of the cask" do
      expect(livecheck.cask_name(c, full_name: true)).to eq("test")
    end
  end

  describe "::status_hash" do
    it "returns a hash containing the livecheck status for a formula" do
      expect(livecheck.status_hash(f, "error", ["Unable to get versions"]))
        .to eq({
          formula:  "test",
          status:   "error",
          messages: ["Unable to get versions"],
          meta:     {
            livecheckable: true,
          },
        })
    end

    it "returns a hash containing the livecheck status for a resource" do
      expect(livecheck.status_hash(r, "error", ["Unable to get versions"]))
        .to eq({
          resource: "foo",
          status:   "error",
          messages: ["Unable to get versions"],
          meta:     {
            livecheckable: true,
          },
        })
    end
  end

  describe "::livecheck_url_to_string" do
    let(:f_livecheck_url) do
      homepage_url_s = homepage_url
      stable_url_s = stable_url
      head_url_s = head_url
      resource_url_s = resource_url

      formula("test_livecheck_url") do
        desc "Test Livecheck URL formula"
        homepage homepage_url_s
        url stable_url_s
        head head_url_s

        resource "foo" do
          url resource_url_s
          sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

          livecheck do
            url "https://brew.sh/test/releases"
            regex(/foo[._-]v?(\d+(?:\.\d+)+)\.t/i)
          end
        end
      end
    end

    let(:r_livecheck_url) { f_livecheck_url.resources.first }

    let(:c_livecheck_url) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "test_livecheck_url" do
          version "0.0.1,2"

          url "https://brew.sh/test-0.0.1.dmg"
          name "Test"
          desc "Test Livecheck URL cask"
          homepage "https://brew.sh"
        end
      RUBY
    end

    it "returns a URL string when given a livecheck_url string for a formula" do
      expect(livecheck.livecheck_url_to_string(livecheck_url, f_livecheck_url)).to eq(livecheck_url)
    end

    it "returns a URL string when given a livecheck_url string for a resource" do
      expect(livecheck.livecheck_url_to_string(livecheck_url, r_livecheck_url)).to eq(livecheck_url)
    end

    it "returns a URL symbol when given a valid livecheck_url symbol" do
      expect(livecheck.livecheck_url_to_string(:head, f_livecheck_url)).to eq(head_url)
      expect(livecheck.livecheck_url_to_string(:homepage, f_livecheck_url)).to eq(homepage_url)
      expect(livecheck.livecheck_url_to_string(:homepage, c_livecheck_url)).to eq(homepage_url)
      expect(livecheck.livecheck_url_to_string(:stable, f_livecheck_url)).to eq(stable_url)
      expect(livecheck.livecheck_url_to_string(:url, c_livecheck_url)).to eq(cask_url)
      expect(livecheck.livecheck_url_to_string(:url, r_livecheck_url)).to eq(resource_url)
    end

    it "returns nil when not given a string or valid symbol" do
      expect(livecheck.livecheck_url_to_string(nil, f_livecheck_url)).to be_nil
      expect(livecheck.livecheck_url_to_string(nil, c_livecheck_url)).to be_nil
      expect(livecheck.livecheck_url_to_string(nil, r_livecheck_url)).to be_nil
      expect(livecheck.livecheck_url_to_string(:invalid_symbol, f_livecheck_url)).to be_nil
      expect(livecheck.livecheck_url_to_string(:invalid_symbol, c_livecheck_url)).to be_nil
      expect(livecheck.livecheck_url_to_string(:invalid_symbol, r_livecheck_url)).to be_nil
    end
  end

  describe "::checkable_urls" do
    let(:resource_url) { "https://brew.sh/foo-1.0.tar.gz" }
    let(:f_duplicate_urls) do
      formula("test_duplicate_urls") do
        desc "Test formula with a duplicate URL"
        homepage "https://github.com/Homebrew/brew.git"
        url "https://brew.sh/test-0.0.1.tgz"
        head "https://github.com/Homebrew/brew.git"
      end
    end

    it "returns the list of URLs to check" do
      expect(livecheck.checkable_urls(f)).to eq([stable_url, head_url, homepage_url])
      expect(livecheck.checkable_urls(c)).to eq([cask_url, homepage_url])
      expect(livecheck.checkable_urls(r)).to eq([resource_url])
      expect(livecheck.checkable_urls(f_duplicate_urls)).to eq([stable_url, head_url])
    end
  end

  describe "::use_homebrew_curl?" do
    let(:example_url) { "https://www.example.com/test-0.0.1.tgz" }

    let(:f_homebrew_curl) do
      formula("test") do
        desc "Test formula"
        homepage "https://brew.sh"
        url "https://brew.sh/test-0.0.1.tgz", using: :homebrew_curl
        # head is deliberably omitted to exercise more of the method

        livecheck do
          url "https://formulae.brew.sh/api/formula/ruby.json"
          regex(/"stable":"(\d+(?:\.\d+)+)"/i)
        end
      end
    end

    let(:c_homebrew_curl) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "test" do
          version "0.0.1,2"

          url "https://brew.sh/test-0.0.1.dmg", using: :homebrew_curl
          name "Test"
          desc "Test cask"
          homepage "https://brew.sh"

          livecheck do
            url "https://formulae.brew.sh/api/formula/ruby.json"
            regex(/"stable":"(\d+(?:.\d+)+)"/i)
          end
        end
      RUBY
    end

    it "returns `true` when URL matches a `using: :homebrew_curl` URL" do
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, livecheck_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, homepage_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, stable_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, livecheck_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, homepage_url)).to be(true)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, cask_url)).to be(true)
    end

    it "returns `false` if URL root domain differs from `using: :homebrew_curl` URLs" do
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, example_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c_homebrew_curl, example_url)).to be(false)
    end

    it "returns `false` if a `using: homebrew_curl` URL is not present" do
      expect(livecheck.use_homebrew_curl?(f, livecheck_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(f, homepage_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(f, stable_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(f, example_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c, livecheck_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c, homepage_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c, cask_url)).to be(false)
      expect(livecheck.use_homebrew_curl?(c, example_url)).to be(false)
    end

    it "returns `false` if URL string does not contain a domain" do
      expect(livecheck.use_homebrew_curl?(f_homebrew_curl, "test")).to be(false)
    end
  end

  describe "::preprocess_url" do
    let(:github_git_url_with_extension) { "https://github.com/Homebrew/brew.git" }

    it "returns the unmodified URL for an unparsable URL" do
      # Modeled after the `head` URL in the `ncp` formula
      expect(livecheck.preprocess_url(":something:cvs:@cvs.brew.sh:/cvs"))
        .to eq(":something:cvs:@cvs.brew.sh:/cvs")
    end

    it "returns the unmodified URL for a GitHub URL ending in .git" do
      expect(livecheck.preprocess_url(github_git_url_with_extension))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a GitHub URL not ending in .git" do
      expect(livecheck.preprocess_url("https://github.com/Homebrew/brew"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the unmodified URL for a GitHub /releases/latest URL" do
      expect(livecheck.preprocess_url("https://github.com/Homebrew/brew/releases/latest"))
        .to eq("https://github.com/Homebrew/brew/releases/latest")
    end

    it "returns the Git repository URL for a GitHub AWS URL" do
      expect(livecheck.preprocess_url("https://github.s3.amazonaws.com/downloads/Homebrew/brew/1.0.0.tar.gz"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a github.com/downloads/... URL" do
      expect(livecheck.preprocess_url("https://github.com/downloads/Homebrew/brew/1.0.0.tar.gz"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a GitHub tag archive URL" do
      expect(livecheck.preprocess_url("https://github.com/Homebrew/brew/archive/1.0.0.tar.gz"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a GitHub release archive URL" do
      expect(livecheck.preprocess_url("https://github.com/Homebrew/brew/releases/download/1.0.0/brew-1.0.0.tar.gz"))
        .to eq(github_git_url_with_extension)
    end

    it "returns the Git repository URL for a gitlab.com archive URL" do
      expect(livecheck.preprocess_url("https://gitlab.com/Homebrew/brew/-/archive/1.0.0/brew-1.0.0.tar.gz"))
        .to eq("https://gitlab.com/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a self-hosted GitLab archive URL" do
      expect(livecheck.preprocess_url("https://brew.sh/Homebrew/brew/-/archive/1.0.0/brew-1.0.0.tar.gz"))
        .to eq("https://brew.sh/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a Codeberg archive URL" do
      expect(livecheck.preprocess_url("https://codeberg.org/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://codeberg.org/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a Gitea archive URL" do
      expect(livecheck.preprocess_url("https://gitea.com/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://gitea.com/Homebrew/brew.git")
    end

    it "returns the Git repository URL for an Opendev archive URL" do
      expect(livecheck.preprocess_url("https://opendev.org/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://opendev.org/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a tildegit archive URL" do
      expect(livecheck.preprocess_url("https://tildegit.org/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://tildegit.org/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a LOL Git archive URL" do
      expect(livecheck.preprocess_url("https://lolg.it/Homebrew/brew/archive/brew-1.0.0.tar.gz"))
        .to eq("https://lolg.it/Homebrew/brew.git")
    end

    it "returns the Git repository URL for a sourcehut archive URL" do
      expect(livecheck.preprocess_url("https://git.sr.ht/~Homebrew/brew/archive/1.0.0.tar.gz"))
        .to eq("https://git.sr.ht/~Homebrew/brew")
    end
  end
end
