# frozen_string_literal: true

require "livecheck/livecheck"

RSpec.describe Homebrew::Livecheck do
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

  let(:f_stable_url_only) do
    stable_url_s = stable_url

    formula("test_stable_url_only") do
      desc "Test formula with only a stable URL"
      url stable_url_s
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

  let(:c_no_checkable_urls) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "test_no_checkable_urls" do
        version "1.2.3"

        name "Test"
        desc "Test cask with no checkable URLs"
      end
    RUBY
  end

  describe "::livecheck_strategy_names" do
    context "when provided with a strategy class" do
      it "returns demodulized class name" do
        # We run this twice with the same argument to exercise the caching logic
        expect(livecheck.send(:livecheck_strategy_names, Homebrew::Livecheck::Strategy::PageMatch)).to eq("PageMatch")
        expect(livecheck.send(:livecheck_strategy_names, Homebrew::Livecheck::Strategy::PageMatch)).to eq("PageMatch")
      end
    end
  end

  describe "::livecheck_find_versions_parameters" do
    context "when provided with a strategy class" do
      it "returns demodulized class name" do
        page_match_parameters = T::Utils.signature_for_method(
          Homebrew::Livecheck::Strategy::PageMatch.method(:find_versions),
        ).parameters.map(&:second)

        # We run this twice with the same argument to exercise the caching logic
        expect(livecheck.send(:livecheck_find_versions_parameters, Homebrew::Livecheck::Strategy::PageMatch))
          .to eq(page_match_parameters)
        expect(livecheck.send(:livecheck_find_versions_parameters, Homebrew::Livecheck::Strategy::PageMatch))
          .to eq(page_match_parameters)
      end
    end
  end

  describe "::resolve_livecheck_reference" do
    context "when a formula/cask has a `livecheck` block without formula/cask methods" do
      it "returns [nil, []]" do
        expect(livecheck.resolve_livecheck_reference(f)).to eq([nil, []])
        expect(livecheck.resolve_livecheck_reference(c)).to eq([nil, []])
      end
    end
  end

  describe "::package_or_resource_name" do
    it "returns the name of a formula" do
      expect(livecheck.package_or_resource_name(f)).to eq("test")
    end

    it "returns the full name of a formula" do
      expect(livecheck.package_or_resource_name(f, full_name: true)).to eq("test")
    end

    it "returns the token of a cask" do
      expect(livecheck.package_or_resource_name(c)).to eq("test")
    end

    it "returns the full name of a cask" do
      expect(livecheck.package_or_resource_name(c, full_name: true)).to eq("test")
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
            livecheck_defined: true,
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
            livecheck_defined: true,
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
      error_text = "`url :%<symbol>s` does not reference a checkable URL"

      # Invalid symbol in any context
      expect { livecheck.livecheck_url_to_string(:invalid_symbol, f_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :invalid_symbol))
      expect { livecheck.livecheck_url_to_string(:invalid_symbol, c_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :invalid_symbol))
      expect { livecheck.livecheck_url_to_string(:invalid_symbol, r_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :invalid_symbol))

      # Valid symbol in provided context but referenced URL is not present
      expect { livecheck.livecheck_url_to_string(:head, f_stable_url_only) }
        .to raise_error(ArgumentError, format(error_text, symbol: :head))
      expect { livecheck.livecheck_url_to_string(:homepage, f_stable_url_only) }
        .to raise_error(ArgumentError, format(error_text, symbol: :homepage))
      expect { livecheck.livecheck_url_to_string(:homepage, c_no_checkable_urls) }
        .to raise_error(ArgumentError, format(error_text, symbol: :homepage))
      expect { livecheck.livecheck_url_to_string(:url, c_no_checkable_urls) }
        .to raise_error(ArgumentError, format(error_text, symbol: :url))

      # Valid symbol but not in the provided context
      expect { livecheck.livecheck_url_to_string(:head, c_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :head))
      expect { livecheck.livecheck_url_to_string(:homepage, r_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :homepage))
      expect { livecheck.livecheck_url_to_string(:stable, c_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :stable))
      expect { livecheck.livecheck_url_to_string(:url, f_livecheck_url) }
        .to raise_error(ArgumentError, format(error_text, symbol: :url))
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
      expect(livecheck.checkable_urls(f_stable_url_only)).to eq([stable_url])
      expect(livecheck.checkable_urls(c_no_checkable_urls)).to eq([])
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
end
