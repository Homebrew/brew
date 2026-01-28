# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy do
  subject(:strategy) { described_class }

  let(:url) { "https://brew.sh/" }
  let(:redirection_url) { "https://brew.sh/redirection" }

  let(:post_hash) do
    {
      empty:   "",
      boolean: "true",
      number:  "1",
      string:  "a + b = c",
    }
  end
  let(:form_string) { "empty=&boolean=true&number=1&string=a+%2B+b+%3D+c" }
  let(:json_string) { '{"empty":"","boolean":"true","number":"1","string":"a + b = c"}' }

  let(:response_hash) do
    response_hash = {}

    response_hash[:ok] = {
      status_code: "200",
      status_text: "OK",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
      },
    }

    response_hash[:redirection] = {
      status_code: "301",
      status_text: "Moved Permanently",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "location"       => redirection_url,
      },
    }

    response_hash
  end

  let(:body) do
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Thank you!</title>
        </head>
        <body>
          <h1>Download</h1>
          <p>This download link could have been made publicly available in a reasonable fashion but we appreciate that you jumped through the hoops that we carefully set up!: <a href="https://brew.sh/example-1.2.3.tar.gz">Example v1.2.3</a></p>
          <p>The current legacy version is: <a href="https://brew.sh/example-0.1.2.tar.gz">Example v0.1.2</a></p>
        </body>
      </html>
    HTML
  end

  let(:response_text) do
    response_text = {}

    response_text[:ok] = <<~EOS
      HTTP/1.1 #{response_hash[:ok][:status_code]} #{response_hash[:ok][:status_text]}\r
      Cache-Control: #{response_hash[:ok][:headers]["cache-control"]}\r
      Content-Type: #{response_hash[:ok][:headers]["content-type"]}\r
      Date: #{response_hash[:ok][:headers]["date"]}\r
      Expires: #{response_hash[:ok][:headers]["expires"]}\r
      Last-Modified: #{response_hash[:ok][:headers]["last-modified"]}\r
      Content-Length: #{response_hash[:ok][:headers]["content-length"]}\r
      \r
      #{body.rstrip}
    EOS

    response_text[:redirection_to_ok] = response_text[:ok].sub(
      "HTTP/1.1 #{response_hash[:ok][:status_code]} #{response_hash[:ok][:status_text]}\r",
      "HTTP/1.1 #{response_hash[:redirection][:status_code]} #{response_hash[:redirection][:status_text]}\r\n" \
      "Location: #{response_hash[:redirection][:headers]["location"]}\r",
    )

    response_text
  end

  describe "::from_symbol" do
    it "returns the Strategy module represented by the Symbol argument" do
      expect(strategy.from_symbol(:page_match)).to eq(Homebrew::Livecheck::Strategy::PageMatch)
    end

    it "returns `nil` if the argument is `nil`" do
      expect(strategy.from_symbol(nil)).to be_nil
    end
  end

  describe "::from_url" do
    let(:sourceforge_url) { "https://sourceforge.net/projects/test" }

    context "when a regex or `strategy` block is not provided" do
      it "returns an array of usable strategies which doesn't include PageMatch" do
        expect(strategy.from_url(sourceforge_url)).to eq([Homebrew::Livecheck::Strategy::Sourceforge])
      end
    end

    context "when a regex or `strategy` block is provided" do
      it "returns an array of usable strategies including PageMatch, sorted in descending order by priority" do
        expect(strategy.from_url(sourceforge_url, regex_provided: true))
          .to eq(
            [Homebrew::Livecheck::Strategy::Sourceforge, Homebrew::Livecheck::Strategy::PageMatch],
          )
      end
    end

    context "when a `strategy` block is required and one is provided" do
      it "returns an array of usable strategies including the specified strategy" do
        # The strategies array is naturally in alphabetic order when all
        # applicable strategies have the same priority
        expect(strategy.from_url(url, livecheck_strategy: :json, block_provided: true))
          .to eq([Homebrew::Livecheck::Strategy::Json, Homebrew::Livecheck::Strategy::PageMatch])
        expect(strategy.from_url(url, livecheck_strategy: :xml, block_provided: true))
          .to eq([Homebrew::Livecheck::Strategy::PageMatch, Homebrew::Livecheck::Strategy::Xml])
        expect(strategy.from_url(url, livecheck_strategy: :yaml, block_provided: true))
          .to eq([Homebrew::Livecheck::Strategy::PageMatch, Homebrew::Livecheck::Strategy::Yaml])
      end
    end

    context "when a `strategy` block is required and one is not provided" do
      it "returns an array of usable strategies not including the specified strategy" do
        expect(strategy.from_url(url, livecheck_strategy: :json, block_provided: false)).to eq([])
        expect(strategy.from_url(url, livecheck_strategy: :xml, block_provided: false)).to eq([])
        expect(strategy.from_url(url, livecheck_strategy: :yaml, block_provided: false)).to eq([])
      end
    end
  end

  describe "::post_args" do
    let(:form_string_content_length) { "Content-Length: #{form_string.length}" }
    let(:json_string_content_length) { "Content-Length: #{json_string.length}" }

    it "returns an array including `--data` and an encoded form data string" do
      expect(strategy.post_args(post_form: post_hash))
        .to eq(["--data", form_string, "--header", form_string_content_length])

      # If both `post_form` and `post_json` are present, only `post_form` will
      # be used.
      expect(strategy.post_args(post_form: post_hash, post_json: post_hash))
        .to eq(["--data", form_string, "--header", form_string_content_length])
    end

    it "returns an array including `--json` and a JSON string" do
      expect(strategy.post_args(post_json: post_hash))
        .to eq(["--json", json_string, "--header", json_string_content_length])
    end

    it "returns an empty array if `post_form` value is blank" do
      expect(strategy.post_args(post_form: {})).to eq([])
    end

    it "returns an empty array if `post_json` value is blank" do
      expect(strategy.post_args(post_json: {})).to eq([])
    end

    it "returns an empty array if hash argument doesn't have a `post_form` or `post_json` value" do
      expect(strategy.post_args).to eq([])
    end
  end

  describe "::page_headers" do
    let(:responses) { [response_hash[:ok]] }

    it "returns headers from fetched content" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(strategy.page_headers(url)).to eq([responses.first[:headers]])
    end

    it "handles `cookies` `url` options" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(
        strategy.page_headers(
          url,
          options: Homebrew::Livecheck::Options.new(
            cookies: { "cookie_key" => "cookie_value" },
          ),
        ),
      ).to eq([responses.first[:headers]])
    end

    it "handles `header` `url` options" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(
        strategy.page_headers(
          url,
          options: Homebrew::Livecheck::Options.new(header: "Accept: */*"),
        ),
      ).to eq([responses.first[:headers]])

      expect(
        strategy.page_headers(
          url,
          options: Homebrew::Livecheck::Options.new(
            header: ["Accept: */*", "X-Requested-With: XMLHttpRequest"],
          ),
        ),
      ).to eq([responses.first[:headers]])
    end

    it "handles `post_form` `url` options" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(
        strategy.page_headers(
          url,
          options: Homebrew::Livecheck::Options.new(post_form: post_hash),
        ),
      ).to eq([responses.first[:headers]])
    end

    it "handles `post_json` `url` options" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(
        strategy.page_headers(
          url,
          options: Homebrew::Livecheck::Options.new(post_json: post_hash),
        ),
      ).to eq([responses.first[:headers]])
    end

    it "handles `referer` `url` option" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(
        strategy.page_headers(
          url,
          options: Homebrew::Livecheck::Options.new(referer: "https://brew.sh/"),
        ),
      ).to eq([responses.first[:headers]])
    end

    it "handles `user_agent` `url` option" do
      allow(strategy).to receive(:curl_headers).and_return({ responses:, body: })

      expect(
        strategy.page_headers(
          url,
          options: Homebrew::Livecheck::Options.new(user_agent: :browser),
        ),
      ).to eq([responses.first[:headers]])
    end

    it "returns an empty array if `curl_headers` only raises an `ErrorDuringExecution` error" do
      allow(strategy).to receive(:curl_headers).and_raise(ErrorDuringExecution.new([], status: 1))

      expect(strategy.page_headers(url)).to eq([])
    end
  end

  describe "::page_content" do
    let(:curl_version) { Version.new("8.7.1") }
    let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

    it "returns hash including fetched content" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(strategy.page_content(url)).to eq({ content: body })
    end

    it "handles `cookies` `url` option" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(
        strategy.page_content(
          url,
          options: Homebrew::Livecheck::Options.new(
            cookies: { "cookie_key" => "cookie_value" },
          ),
        ),
      ).to eq({ content: body })
    end

    it "handles `header` `url` option" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(
        strategy.page_content(
          url,
          options: Homebrew::Livecheck::Options.new(header: "Accept: */*"),
        ),
      ).to eq({ content: body })

      expect(
        strategy.page_content(
          url,
          options: Homebrew::Livecheck::Options.new(
            header: ["Accept: */*", "X-Requested-With: XMLHttpRequest"],
          ),
        ),
      ).to eq({ content: body })
    end

    it "handles `post_form` `url` option" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(
        strategy.page_content(
          url,
          options: Homebrew::Livecheck::Options.new(post_form: post_hash),
        ),
      ).to eq({ content: body })
    end

    it "handles `post_json` `url` option" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(
        strategy.page_content(
          url,
          options: Homebrew::Livecheck::Options.new(post_json: post_hash),
        ),
      ).to eq({ content: body })
    end

    it "handles `referer` `url` option" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(
        strategy.page_content(
          url,
          options: Homebrew::Livecheck::Options.new(referer: "https://brew.sh/"),
        ),
      ).to eq({ content: body })
    end

    it "handles `user_agent` `url` option" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:ok], nil, success_status])

      expect(
        strategy.page_content(
          url,
          options: Homebrew::Livecheck::Options.new(user_agent: :browser),
        ),
      ).to eq({ content: body })
    end

    it "returns error `messages` from `stderr` in the return hash on failure when `stderr` is not `nil`" do
      error_message = "curl: (6) Could not resolve host: brew.sh"
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([
        nil,
        error_message,
        instance_double(Process::Status, success?: false, exitstatus: 6),
      ])

      expect(strategy.page_content(url)).to eq({ messages: [error_message] })
    end

    it "returns default error `messages` in the return hash on failure when `stderr` is `nil`" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([
        nil,
        nil,
        instance_double(Process::Status, success?: false, exitstatus: 1),
      ])

      expect(strategy.page_content(url)).to eq({ messages: ["cURL failed without a detectable error"] })
    end

    it "returns hash including `final_url` if it differs from initial `url`" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(curl_version)
      allow(strategy).to receive(:curl_output).and_return([response_text[:redirection_to_ok], nil, success_status])

      expect(strategy.page_content(url)).to eq({ content: body, final_url: redirection_url })
    end
  end

  describe "::handle_block_return" do
    it "returns an array of version strings when given a valid value" do
      expect(strategy.handle_block_return("1.2.3")).to eq(["1.2.3"])
      expect(strategy.handle_block_return(["1.2.3", "1.2.4"])).to eq(["1.2.3", "1.2.4"])
    end

    it "returns an empty array when given a nil value" do
      expect(strategy.handle_block_return(nil)).to eq([])
    end

    it "errors when given an invalid value" do
      expect { strategy.handle_block_return(123) }
        .to raise_error(TypeError, strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end
end
