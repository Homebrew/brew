# typed: false
# frozen_string_literal: true

require "utils/curl"

describe "Utils::Curl" do
  let(:location_urls) {
    %w[
      https://example.com/example/
      https://example.com/example1/
      https://example.com/example2/
    ]
  }

  let(:head_hash) {
    head_hash = {}

    head_hash[:ok] = {
      status_code: "200",
      status_desc: "OK",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
      },
    }

    head_hash[:redirection] = {
      status_code: "301",
      status_desc: "Moved Permanently",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "location"       => location_urls[0],
      },
    }

    head_hash[:redirection1] = {
      status_code: "301",
      status_desc: "Moved Permanently",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "location"       => location_urls[1],
      },
    }

    head_hash[:redirection2] = {
      status_code: "301",
      status_desc: "Moved Permanently",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "location"       => location_urls[2],
      },
    }

    head_hash[:redirection_no_scheme] = {
      status_code: "301",
      status_desc: "Moved Permanently",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "location"       => "//www.example.com/example/",
      },
    }

    head_hash[:redirection_root_relative] = {
      status_code: "301",
      status_desc: "Moved Permanently",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "location"       => "/example/",
      },
    }

    head_hash[:redirection_parent_relative] = {
      status_code: "301",
      status_desc: "Moved Permanently",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "location"       => "./example/",
      },
    }

    head_hash
  }

  let(:head) {
    head = {}

    head[:ok] = <<~EOS
      HTTP/1.1 #{head_hash[:ok][:status_code]} #{head_hash[:ok][:status_desc]}\r
      Cache-Control: #{head_hash[:ok][:headers]["cache-control"]}\r
      Content-Type: #{head_hash[:ok][:headers]["content-type"]}\r
      Date: #{head_hash[:ok][:headers]["date"]}\r
      Expires: #{head_hash[:ok][:headers]["expires"]}\r
      Last-Modified: #{head_hash[:ok][:headers]["last-modified"]}\r
      Content-Length: #{head_hash[:ok][:headers]["content-length"]}\r
      \r
    EOS

    head[:redirection] = head[:ok].sub(
      "HTTP/1.1 #{head_hash[:ok][:status_code]} #{head_hash[:ok][:status_desc]}\r",
      "HTTP/1.1 #{head_hash[:redirection][:status_code]} #{head_hash[:redirection][:status_desc]}\r\n" \
      "Location: #{head_hash[:redirection][:headers]["location"]}\r",
    )

    head[:redirection_to_ok] = "#{head[:redirection]}#{head[:ok]}"

    head[:redirections_to_ok] = <<~EOS
      #{head[:redirection].sub(location_urls[0], location_urls[2])}
      #{head[:redirection].sub(location_urls[0], location_urls[1])}
      #{head[:redirection]}
      #{head[:ok]}
    EOS

    head
  }

  let(:body) {
    body = {}

    body[:default] = <<~EOS
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf-8">
          <title>Example</title>
        </head>
        <body>
          <h1>Example</h1>
          <p>Hello, world!</p>
        </body>
      </html>
    EOS

    body[:with_carriage_returns] = body[:default].sub("<html>\n", "<html>\r\n\r\n")

    body[:with_http_status_line] = body[:default].sub("<html>", "HTTP/1.1 200\r\n<html>")

    body
  }

  describe "curl_args" do
    let(:args) { "foo" }
    let(:user_agent_string) { "Lorem ipsum dolor sit amet" }

    it "returns --disable as the first argument when HOMEBREW_CURLRC is not set" do
      # --disable must be the first argument according to "man curl"
      expect(curl_args(*args).first).to eq("--disable")
    end

    it "doesn't return `--disable` as the first argument when HOMEBREW_CURLRC is set" do
      ENV["HOMEBREW_CURLRC"] = "1"
      expect(curl_args(*args).first).not_to eq("--disable")
    end

    it "uses `--retry 3` when HOMEBREW_CURL_RETRIES is unset" do
      expect(curl_args(*args).join(" ")).to include("--retry 3")
    end

    it "uses the given value for `--retry` when HOMEBREW_CURL_RETRIES is set" do
      ENV["HOMEBREW_CURL_RETRIES"] = "10"
      expect(curl_args(*args).join(" ")).to include("--retry 10")
    end

    it "doesn't use `--retry` when `:retry` == `false`" do
      expect(curl_args(*args, retry: false).join(" ")).not_to include("--retry")
    end

    it "uses `--retry 3` when `:retry` == `true`" do
      expect(curl_args(*args, retry: true).join(" ")).to include("--retry 3")
    end

    it "uses HOMEBREW_USER_AGENT_FAKE_SAFARI when `:user_agent` is `:browser` or `:fake`" do
      expect(curl_args(*args, user_agent: :browser).join(" "))
        .to include("--user-agent #{HOMEBREW_USER_AGENT_FAKE_SAFARI}")
      expect(curl_args(*args, user_agent: :fake).join(" "))
        .to include("--user-agent #{HOMEBREW_USER_AGENT_FAKE_SAFARI}")
    end

    it "uses HOMEBREW_USER_AGENT_CURL when `:user_agent` is `:default` or omitted" do
      expect(curl_args(*args, user_agent: :default).join(" ")).to include("--user-agent #{HOMEBREW_USER_AGENT_CURL}")
      expect(curl_args(*args, user_agent: nil).join(" ")).to include("--user-agent #{HOMEBREW_USER_AGENT_CURL}")
      expect(curl_args(*args).join(" ")).to include("--user-agent #{HOMEBREW_USER_AGENT_CURL}")
    end

    it "uses provided user agent string when `:user_agent` is a `String`" do
      expect(curl_args(*args, user_agent: user_agent_string).join(" "))
        .to include("--user-agent #{user_agent_string}")
    end

    it "uses `--fail` unless `:show_output` is `true`" do
      expect(curl_args(*args, show_output: false).join(" ")).to include("--fail")
      expect(curl_args(*args, show_output: nil).join(" ")).to include("--fail")
      expect(curl_args(*args).join(" ")).to include("--fail")
      expect(curl_args(*args, show_output: true).join(" ")).not_to include("--fail")
    end
  end

  describe "#parse_curl_output" do
    it "returns a correct hash when curl output contains head(s) and body" do
      expect(parse_curl_output("#{head[:ok]}#{body[:default]}"))
        .to eq({ heads: [head_hash[:ok]], body: body[:default] })
      expect(parse_curl_output("#{head[:ok]}#{body[:with_carriage_returns]}"))
        .to eq({ heads: [head_hash[:ok]], body: body[:with_carriage_returns] })
      expect(parse_curl_output("#{head[:ok]}#{body[:with_http_status_line]}"))
        .to eq({ heads: [head_hash[:ok]], body: body[:with_http_status_line] })
      expect(parse_curl_output("#{head[:redirection_to_ok]}#{body[:default]}"))
        .to eq({ heads: [head_hash[:redirection], head_hash[:ok]], body: body[:default] })
      expect(parse_curl_output("#{head[:redirections_to_ok]}#{body[:default]}"))
        .to eq({ heads: [head_hash[:redirection2], head_hash[:redirection1], head_hash[:redirection], head_hash[:ok]],
                 body:  body[:default] })
    end

    it "returns a correct hash when curl output contains head and no body" do
      expect(parse_curl_output(head[:ok])).to eq({ heads: [head_hash[:ok]], body: "" })
    end

    it "returns a correct hash when curl output contains body and no head" do
      expect(parse_curl_output(body[:default])).to eq({ heads: [], body: body[:default] })
      expect(parse_curl_output(body[:with_carriage_returns]))
        .to eq({ heads: [], body: body[:with_carriage_returns] })
      expect(parse_curl_output(body[:with_http_status_line]))
        .to eq({ heads: [], body: body[:with_http_status_line] })
    end

    it "returns correct hash when curl output is blank" do
      expect(parse_curl_output("")).to eq({ heads: [], body: "" })
      expect(parse_curl_output(nil)).to eq({ heads: [], body: "" })
    end
  end

  describe "#parse_curl_head" do
    it "returns a correct hash when given a head string" do
      expect(parse_curl_head(head[:ok])).to eq(head_hash[:ok])
      expect(parse_curl_head(head[:redirection])).to eq(head_hash[:redirection])
    end

    it "returns an empty hash when not given a head string" do
      expect(parse_curl_head("")).to eq({})
      expect(parse_curl_head(nil)).to eq({})
    end
  end

  describe "#curl_response_status_code" do
    it "returns the status code when given an array of head hashes" do
      expect(curl_response_status_code([head_hash[:ok]])).to eq(head_hash[:ok][:status_code])
      expect(curl_response_status_code([head_hash[:redirection], head_hash[:ok]])).to eq(head_hash[:ok][:status_code])
    end

    it "returns nil when argument is not an array" do
      expect(curl_response_status_code({})).to be nil
      expect(curl_response_status_code(nil)).to be nil
    end

    it "returns nil when last array member is not a hash" do
      expect(curl_response_status_code([{}, nil])).to be nil
    end
  end

  describe "#curl_response_last_location" do
    it "returns the last location header when given an array of head hashes" do
      expect(curl_response_last_location([
        head_hash[:redirection],
        head_hash[:ok],
      ])).to eq(head_hash[:redirection][:headers]["location"])

      expect(curl_response_last_location([
        head_hash[:redirection2],
        head_hash[:redirection1],
        head_hash[:redirection],
        head_hash[:ok],
      ])).to eq(head_hash[:redirection][:headers]["location"])
    end

    it "returns the location as given by default or when absolutize is false" do
      expect(curl_response_last_location([
        head_hash[:redirection_no_scheme],
        head_hash[:ok],
      ])).to eq(head_hash[:redirection_no_scheme][:headers]["location"])

      expect(curl_response_last_location([
        head_hash[:redirection_root_relative],
        head_hash[:ok],
      ])).to eq(head_hash[:redirection_root_relative][:headers]["location"])

      expect(curl_response_last_location([
        head_hash[:redirection_parent_relative],
        head_hash[:ok],
      ])).to eq(head_hash[:redirection_parent_relative][:headers]["location"])
    end

    it "returns an absolute URL when given a base URL and absolutize is true" do
      expect(
        curl_response_last_location(
          [head_hash[:redirection_no_scheme], head_hash[:ok]],
          url:        "https://brew.sh/test",
          absolutize: true,
        ),
      ).to eq("https:#{head_hash[:redirection_no_scheme][:headers]["location"]}")

      expect(
        curl_response_last_location(
          [head_hash[:redirection_root_relative], head_hash[:ok]],
          url:        "https://brew.sh/test",
          absolutize: true,
        ),
      ).to eq("https://brew.sh#{head_hash[:redirection_root_relative][:headers]["location"]}")

      expect(
        curl_response_last_location(
          [head_hash[:redirection_parent_relative], head_hash[:ok]],
          url:        "https://brew.sh/test1/test2",
          absolutize: true,
        ),
      ).to eq(head_hash[:redirection_parent_relative][:headers]["location"].sub(/^\./, "https://brew.sh/test1"))
    end

    it "returns nil when the head hash doesn't contain a location header" do
      expect(curl_response_last_location([head_hash[:ok]])).to be nil
    end

    it "returns nil when argument is not an array" do
      expect(curl_response_last_location(nil)).to be nil
    end
  end
end
