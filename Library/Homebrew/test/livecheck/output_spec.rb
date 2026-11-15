# typed: true
# frozen_string_literal: true

require "livecheck/livecheck"

RSpec.describe Homebrew::Livecheck::Output do
  subject(:livecheck) { Homebrew::Livecheck }

  describe "#url_metadata" do
    it "omits unchanged URLs and absent options" do
      expect(livecheck.url_metadata(original_url: "https://brew.sh", url: "https://brew.sh", url_symbol: nil,
                                    strategy_url: "https://brew.sh", final_url: nil, url_options: {}))
        .to eq(original: "https://brew.sh")
    end

    it "preserves each stage of URL resolution and explicit false options" do
      expect(livecheck.url_metadata(original_url: "https://brew.sh", url: "https://brew.sh/releases",
                                    url_symbol: :homepage, strategy_url: "https://brew.sh/api", final_url: "https://cdn.brew.sh",
                                    url_options: { compressed: false }))
        .to eq(symbol: :homepage, original: "https://brew.sh", processed: "https://brew.sh/releases",
               strategy: "https://brew.sh/api", final: "https://cdn.brew.sh", options: { compressed: false })
    end

    it "omits blank strategy URLs but preserves an empty final URL" do
      expect(livecheck.url_metadata(original_url: "https://brew.sh", url: "https://brew.sh", url_symbol: nil,
                                    strategy_url: "", final_url: "", url_options: {}))
        .to eq(original: "https://brew.sh", final: "")
    end
  end

  describe "#report_error" do
    let(:resource) { Resource.new("test-resource") }

    it "returns structured errors for JSON output" do
      expect(livecheck.report_error(resource, StandardError.new("check failed"), json: true))
        .to include(resource: "test-resource", status: "error", messages: ["check failed"])
    end

    it "suppresses structured errors in quiet mode" do
      expect(livecheck.report_error(resource, StandardError.new("check failed"), json: true, quiet: true)).to be_nil
    end

    it "suppresses human-readable errors in quiet mode" do
      expect { livecheck.report_error(resource, StandardError.new("check failed"), quiet: true) }
        .not_to output.to_stderr
    end

    it "prints the resource name and error" do
      expect { livecheck.report_error(resource, StandardError.new("check failed")) }
        .to output(/test-resource: check failed/).to_stderr
    end

    it "adds the disambiguating cask label" do
      expect { livecheck.report_error(resource, StandardError.new("check failed"), ambiguous_cask: true) }
        .to output(/test-resource \(cask\): check failed/).to_stderr
    end

    it "includes a backtrace for unexpected errors in debug mode" do
      error = StandardError.new("check failed")
      error.set_backtrace(["example.rb:1"])

      expect { livecheck.report_error(resource, error, debug: true) }
        .to output(/check failed.*example\.rb:1/m).to_stderr
    end

    it "omits backtraces for expected livecheck errors" do
      error = Homebrew::Livecheck::Error.new("check failed")
      error.set_backtrace(["example.rb:1"])

      expect { livecheck.report_error(resource, error, debug: true) }
        .to output(/check failed/).to_stderr.and not_to_output(/example\.rb:1/).to_stderr
    end
  end
end
