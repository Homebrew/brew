# frozen_string_literal: true

require "utils/curl"

describe "Utils::Curl" do
  include Utils::Curl

  let(:details) do
    details = {
      normal:     {},
      cloudflare: {},
      incapsula:  {},
    }

    details[:normal][:no_cookie] = {
      url:            "https://www.example.com/",
      final_url:      nil,
      status_code:    "403",
      headers:        {
        "age"            => "123456",
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "etag"           => "\"3147526947+ident\"",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Wed, 1 Jan 2020 00:00:00 GMT",
        "server"         => "ECS (dcb/7EA2)",
        "vary"           => "Accept-Encoding",
        "x-cache"        => "HIT",
        "content-length" => "3",
      },
      etag:           "3147526947+ident",
      content_length: "3",
      file:           "...",
      file_hash:      nil,
    }

    details[:normal][:ok] = Marshal.load(Marshal.dump(details[:normal][:no_cookie]))
    details[:normal][:ok][:status_code] = "200"

    details[:normal][:single_cookie] = Marshal.load(Marshal.dump(details[:normal][:no_cookie]))
    details[:normal][:single_cookie][:headers]["set-cookie"] = "a_cookie=for_testing"

    details[:normal][:multiple_cookies] = Marshal.load(Marshal.dump(details[:normal][:no_cookie]))
    details[:normal][:multiple_cookies][:headers]["set-cookie"] = [
      "first_cookie=for_testing",
      "last_cookie=also_for_testing",
    ]

    details[:normal][:blank_headers] = Marshal.load(Marshal.dump(details[:normal][:no_cookie]))
    details[:normal][:blank_headers][:headers] = {}

    details[:cloudflare][:single_cookie] = {
      url:            "https://www.example.com/",
      final_url:      nil,
      status_code:    "403",
      headers:        {
        "date"            => "Wed, 1 Jan 2020 01:23:45 GMT",
        "content-type"    => "text/plain; charset=UTF-8",
        "content-length"  => "16",
        "x-frame-options" => "SAMEORIGIN",
        "referrer-policy" => "same-origin",
        "cache-control"   => "private, max-age=0, no-store, no-cache, must-revalidate, post-check=0, pre-check=0",
        "expires"         => "Thu, 01 Jan 1970 00:00:01 GMT",
        "expect-ct"       => "max-age=604800, report-uri=\"https://report-uri.cloudflare.com/cdn-cgi/beacon/expect-ct\"",
        "set-cookie"      => "__cf_bm=0123456789abcdef; path=/; expires=Wed, 31-Jan-20 01:23:45 GMT; " \
                             "domain=www.example.com; HttpOnly; Secure; SameSite=None",
        "server"          => "cloudflare",
        "cf-ray"          => "0123456789abcdef-IAD",
        "alt-svc"         => "h3=\":443\"; ma=86400, h3-29=\":443\"; ma=86400",
      },
      etag:           nil,
      content_length: "16",
      file:           "error code: 1020",
      file_hash:      nil,
    }

    details[:cloudflare][:multiple_cookies] = Marshal.load(Marshal.dump(details[:cloudflare][:single_cookie]))
    details[:cloudflare][:multiple_cookies][:headers]["set-cookie"] = [
      "first_cookie=for_testing",
      "__cf_bm=abcdef0123456789; path=/; expires=Thu, 28-Apr-22 18:38:40 GMT; domain=www.example.com; HttpOnly; " \
      "Secure; SameSite=None",
      "last_cookie=also_for_testing",
    ]

    details[:cloudflare][:no_server] = Marshal.load(Marshal.dump(details[:cloudflare][:single_cookie]))
    details[:cloudflare][:no_server][:headers].delete("server")

    details[:cloudflare][:wrong_server] = Marshal.load(Marshal.dump(details[:cloudflare][:single_cookie]))
    details[:cloudflare][:wrong_server][:headers]["server"] = "nginx 1.2.3"

    # TODO: Make the Incapsula test data more realistic once we can find an
    # example website to reference.
    details[:incapsula][:single_cookie_visid_incap] = Marshal.load(Marshal.dump(details[:normal][:no_cookie]))
    details[:incapsula][:single_cookie_visid_incap][:headers]["set-cookie"] = "visid_incap_something=something"

    details[:incapsula][:single_cookie_incap_ses] = Marshal.load(Marshal.dump(details[:normal][:no_cookie]))
    details[:incapsula][:single_cookie_incap_ses][:headers]["set-cookie"] = "incap_ses_something=something"

    details[:incapsula][:multiple_cookies_visid_incap] = Marshal.load(Marshal.dump(details[:normal][:no_cookie]))
    details[:incapsula][:multiple_cookies_visid_incap][:headers]["set-cookie"] = [
      "first_cookie=for_testing",
      "visid_incap_something=something",
      "last_cookie=also_for_testing",
    ]

    details[:incapsula][:multiple_cookies_incap_ses] = Marshal.load(Marshal.dump(details[:normal][:no_cookie]))
    details[:incapsula][:multiple_cookies_incap_ses][:headers]["set-cookie"] = [
      "first_cookie=for_testing",
      "incap_ses_something=something",
      "last_cookie=also_for_testing",
    ]

    details
  end

  let(:location_urls) do
    %w[
      https://example.com/example/
      https://example.com/example1/
      https://example.com/example2/
    ]
  end

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
        "location"       => location_urls[0],
      },
    }

    response_hash[:redirection1] = {
      status_code: "301",
      status_text: "Moved Permanently",
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

    response_hash[:redirection2] = {
      status_code: "301",
      status_text: "Moved Permanently",
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

    response_hash[:redirection_no_scheme] = {
      status_code: "301",
      status_text: "Moved Permanently",
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

    response_hash[:redirection_root_relative] = {
      status_code: "301",
      status_text: "Moved Permanently",
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

    response_hash[:redirection_parent_relative] = {
      status_code: "301",
      status_text: "Moved Permanently",
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

    response_hash[:duplicate_header] = {
      status_code: "200",
      status_text: "OK",
      headers:     {
        "cache-control"  => "max-age=604800",
        "content-type"   => "text/html; charset=UTF-8",
        "date"           => "Wed, 1 Jan 2020 01:23:45 GMT",
        "expires"        => "Wed, 31 Jan 2020 01:23:45 GMT",
        "last-modified"  => "Thu, 1 Jan 2019 01:23:45 GMT",
        "content-length" => "123",
        "set-cookie"     => [
          "example1=first",
          "example2=second; Expires Wed, 31 Jan 2020 01:23:45 GMT",
          "example3=third",
        ],
      },
    }

    response_hash
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
    EOS

    response_text[:redirection] = response_text[:ok].sub(
      "HTTP/1.1 #{response_hash[:ok][:status_code]} #{response_hash[:ok][:status_text]}\r",
      "HTTP/1.1 #{response_hash[:redirection][:status_code]} #{response_hash[:redirection][:status_text]}\r\n" \
      "Location: #{response_hash[:redirection][:headers]["location"]}\r",
    )

    response_text[:redirection_to_ok] = "#{response_text[:redirection]}#{response_text[:ok]}"

    response_text[:redirections_to_ok] = <<~EOS
      #{response_text[:redirection].sub(location_urls[0], location_urls[2])}
      #{response_text[:redirection].sub(location_urls[0], location_urls[1])}
      #{response_text[:redirection]}
      #{response_text[:ok]}
    EOS

    response_text[:duplicate_header] = response_text[:ok].sub(
      /\r\n\Z/,
      "Set-Cookie: #{response_hash[:duplicate_header][:headers]["set-cookie"][0]}\r\n" \
      "Set-Cookie: #{response_hash[:duplicate_header][:headers]["set-cookie"][1]}\r\n" \
      "Set-Cookie: #{response_hash[:duplicate_header][:headers]["set-cookie"][2]}\r\n\r\n",
    )

    response_text
  end

  let(:body) do
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
  end

  describe "curl_args" do
    let(:args) { ["foo"] }
    let(:user_agent_string) { "Lorem ipsum dolor sit amet" }

    it "returns `--disable` as the first argument when HOMEBREW_CURLRC is not set" do
      # --disable must be the first argument according to "man curl"
      expect(curl_args(*args).first).to eq("--disable")
    end

    it "doesn't return `--disable` as the first argument when HOMEBREW_CURLRC is set but not a path" do
      ENV["HOMEBREW_CURLRC"] = "1"
      expect(curl_args(*args).first).not_to eq("--disable")
    end

    it "doesn't return `--config` when HOMEBREW_CURLRC is unset" do
      expect(curl_args(*args)).not_to include(a_string_starting_with("--config"))
    end

    it "returns `--config` when HOMEBREW_CURLRC is a valid path" do
      Tempfile.create do |tmpfile|
        path = tmpfile.path
        ENV["HOMEBREW_CURLRC"] = path
        # We still expect --disable
        expect(curl_args(*args).first).to eq("--disable")
        expect(curl_args(*args).join(" ")).to include("--config #{path}")
      end
    ensure
      ENV["HOMEBREW_CURLRC"] = nil
    end

    it "uses `--connect-timeout` when `:connect_timeout` is Numeric" do
      expect(curl_args(*args, connect_timeout: 123).join(" ")).to include("--connect-timeout 123")
      expect(curl_args(*args, connect_timeout: 123.4).join(" ")).to include("--connect-timeout 123.4")
      expect(curl_args(*args, connect_timeout: 123.4567).join(" ")).to include("--connect-timeout 123.457")
    end

    it "errors when `:connect_timeout` is not Numeric" do
      expect { curl_args(*args, connect_timeout: "test") }.to raise_error(TypeError)
    end

    it "uses `--max-time` when `:max_time` is Numeric" do
      expect(curl_args(*args, max_time: 123).join(" ")).to include("--max-time 123")
      expect(curl_args(*args, max_time: 123.4).join(" ")).to include("--max-time 123.4")
      expect(curl_args(*args, max_time: 123.4567).join(" ")).to include("--max-time 123.457")
    end

    it "errors when `:max_time` is not Numeric" do
      expect { curl_args(*args, max_time: "test") }.to raise_error(TypeError)
    end

    it "uses `--retry 3` when HOMEBREW_CURL_RETRIES is unset" do
      expect(curl_args(*args).join(" ")).to include("--retry 3")
    end

    it "uses the given value for `--retry` when HOMEBREW_CURL_RETRIES is set" do
      ENV["HOMEBREW_CURL_RETRIES"] = "10"
      expect(curl_args(*args).join(" ")).to include("--retry 10")
    end

    it "uses `--retry` when `:retries` is a positive Integer" do
      expect(curl_args(*args, retries: 5).join(" ")).to include("--retry 5")
    end

    it "doesn't use `--retry` when `:retries` is nil or a non-positive Integer" do
      expect(curl_args(*args, retries: nil).join(" ")).not_to include("--retry")
      expect(curl_args(*args, retries: 0).join(" ")).not_to include("--retry")
      expect(curl_args(*args, retries: -1).join(" ")).not_to include("--retry")
    end

    it "errors when `:retries` is not Numeric" do
      expect { curl_args(*args, retries: "test") }.to raise_error(TypeError)
    end

    it "uses `--retry-max-time` when `:retry_max_time` is Numeric" do
      expect(curl_args(*args, retry_max_time: 123).join(" ")).to include("--retry-max-time 123")
      expect(curl_args(*args, retry_max_time: 123.4).join(" ")).to include("--retry-max-time 123")
    end

    it "errors when `:retry_max_time` is not Numeric" do
      expect { curl_args(*args, retry_max_time: "test") }.to raise_error(TypeError)
    end

    it "uses `--referer` when :referer is present" do
      expect(curl_args(*args, referer: "https://brew.sh").join(" ")).to include("--referer https://brew.sh")
    end

    it "doesn't use `--referer` when :referer is nil" do
      expect(curl_args(*args, referer: nil).join(" ")).not_to include("--referer")
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

    it "errors when `:user_agent` is not a String or supported Symbol" do
      expect { curl_args(*args, user_agent: :an_unsupported_symbol) }
        .to raise_error(TypeError, ":user_agent must be :browser/:fake, :default, or a String")
      expect { curl_args(*args, user_agent: 123) }.to raise_error(TypeError)
    end

    it "uses `--fail` unless `:show_output` is `true`" do
      expect(curl_args(*args, show_output: false).join(" ")).to include("--fail")
      expect(curl_args(*args, show_output: nil).join(" ")).to include("--fail")
      expect(curl_args(*args).join(" ")).to include("--fail")
      expect(curl_args(*args, show_output: true).join(" ")).not_to include("--fail")
    end
  end

  describe "url_protected_by_cloudflare?" do
    it "returns `true` when a URL is protected by Cloudflare" do
      expect(url_protected_by_cloudflare?(details[:cloudflare][:single_cookie])).to be(true)
      expect(url_protected_by_cloudflare?(details[:cloudflare][:multiple_cookies])).to be(true)
    end

    it "returns `false` when a URL is not protected by Cloudflare" do
      expect(url_protected_by_cloudflare?(details[:cloudflare][:no_server])).to be(false)
      expect(url_protected_by_cloudflare?(details[:cloudflare][:wrong_server])).to be(false)
      expect(url_protected_by_cloudflare?(details[:normal][:no_cookie])).to be(false)
      expect(url_protected_by_cloudflare?(details[:normal][:ok])).to be(false)
      expect(url_protected_by_cloudflare?(details[:normal][:single_cookie])).to be(false)
      expect(url_protected_by_cloudflare?(details[:normal][:multiple_cookies])).to be(false)
    end

    it "returns `false` when response headers are blank" do
      expect(url_protected_by_cloudflare?(details[:normal][:blank_headers])).to be(false)
    end
  end

  describe "url_protected_by_incapsula?" do
    it "returns `true` when a URL is protected by Cloudflare" do
      expect(url_protected_by_incapsula?(details[:incapsula][:single_cookie_visid_incap])).to be(true)
      expect(url_protected_by_incapsula?(details[:incapsula][:single_cookie_incap_ses])).to be(true)
      expect(url_protected_by_incapsula?(details[:incapsula][:multiple_cookies_visid_incap])).to be(true)
      expect(url_protected_by_incapsula?(details[:incapsula][:multiple_cookies_incap_ses])).to be(true)
    end

    it "returns `false` when a URL is not protected by Incapsula" do
      expect(url_protected_by_incapsula?(details[:normal][:no_cookie])).to be(false)
      expect(url_protected_by_incapsula?(details[:normal][:ok])).to be(false)
      expect(url_protected_by_incapsula?(details[:normal][:single_cookie])).to be(false)
      expect(url_protected_by_incapsula?(details[:normal][:multiple_cookies])).to be(false)
    end

    it "returns `false` when response headers are blank" do
      expect(url_protected_by_incapsula?(details[:normal][:blank_headers])).to be(false)
    end
  end

  describe "#parse_curl_output" do
    it "returns a correct hash when curl output contains response(s) and body" do
      expect(parse_curl_output("#{response_text[:ok]}#{body[:default]}"))
        .to eq({ responses: [response_hash[:ok]], body: body[:default] })
      expect(parse_curl_output("#{response_text[:ok]}#{body[:with_carriage_returns]}"))
        .to eq({ responses: [response_hash[:ok]], body: body[:with_carriage_returns] })
      expect(parse_curl_output("#{response_text[:ok]}#{body[:with_http_status_line]}"))
        .to eq({ responses: [response_hash[:ok]], body: body[:with_http_status_line] })
      expect(parse_curl_output("#{response_text[:redirection_to_ok]}#{body[:default]}"))
        .to eq({ responses: [response_hash[:redirection], response_hash[:ok]], body: body[:default] })
      expect(parse_curl_output("#{response_text[:redirections_to_ok]}#{body[:default]}"))
        .to eq({
          responses: [
            response_hash[:redirection2],
            response_hash[:redirection1],
            response_hash[:redirection],
            response_hash[:ok],
          ],
          body:      body[:default],
        })
    end

    it "returns a correct hash when curl output contains HTTP response text and no body" do
      expect(parse_curl_output(response_text[:ok])).to eq({ responses: [response_hash[:ok]], body: "" })
    end

    it "returns a correct hash when curl output contains body and no HTTP response text" do
      expect(parse_curl_output(body[:default])).to eq({ responses: [], body: body[:default] })
      expect(parse_curl_output(body[:with_carriage_returns]))
        .to eq({ responses: [], body: body[:with_carriage_returns] })
      expect(parse_curl_output(body[:with_http_status_line]))
        .to eq({ responses: [], body: body[:with_http_status_line] })
    end

    it "returns correct hash when curl output is blank" do
      expect(parse_curl_output("")).to eq({ responses: [], body: "" })
    end
  end

  describe "#parse_curl_response" do
    it "returns a correct hash when given HTTP response text" do
      expect(parse_curl_response(response_text[:ok])).to eq(response_hash[:ok])
      expect(parse_curl_response(response_text[:redirection])).to eq(response_hash[:redirection])
      expect(parse_curl_response(response_text[:duplicate_header])).to eq(response_hash[:duplicate_header])
    end

    it "returns an empty hash when given an empty string" do
      expect(parse_curl_response("")).to eq({})
    end
  end

  describe "#curl_response_last_location" do
    it "returns the last location header when given an array of HTTP response hashes" do
      expect(curl_response_last_location([
        response_hash[:redirection],
        response_hash[:ok],
      ])).to eq(response_hash[:redirection][:headers]["location"])

      expect(curl_response_last_location([
        response_hash[:redirection2],
        response_hash[:redirection1],
        response_hash[:redirection],
        response_hash[:ok],
      ])).to eq(response_hash[:redirection][:headers]["location"])
    end

    it "returns the location as given, by default or when absolutize is false" do
      expect(curl_response_last_location([
        response_hash[:redirection_no_scheme],
        response_hash[:ok],
      ])).to eq(response_hash[:redirection_no_scheme][:headers]["location"])

      expect(curl_response_last_location([
        response_hash[:redirection_root_relative],
        response_hash[:ok],
      ])).to eq(response_hash[:redirection_root_relative][:headers]["location"])

      expect(curl_response_last_location([
        response_hash[:redirection_parent_relative],
        response_hash[:ok],
      ])).to eq(response_hash[:redirection_parent_relative][:headers]["location"])
    end

    it "returns an absolute URL when absolutize is true and a base URL is provided" do
      expect(
        curl_response_last_location(
          [response_hash[:redirection_no_scheme], response_hash[:ok]],
          absolutize: true,
          base_url:   "https://brew.sh/test",
        ),
      ).to eq("https:#{response_hash[:redirection_no_scheme][:headers]["location"]}")

      expect(
        curl_response_last_location(
          [response_hash[:redirection_root_relative], response_hash[:ok]],
          absolutize: true,
          base_url:   "https://brew.sh/test",
        ),
      ).to eq("https://brew.sh#{response_hash[:redirection_root_relative][:headers]["location"]}")

      expect(
        curl_response_last_location(
          [response_hash[:redirection_parent_relative], response_hash[:ok]],
          absolutize: true,
          base_url:   "https://brew.sh/test1/test2",
        ),
      ).to eq(response_hash[:redirection_parent_relative][:headers]["location"].sub(/^\./, "https://brew.sh/test1"))
    end

    it "returns nil when the response hash doesn't contain a location header" do
      expect(curl_response_last_location([response_hash[:ok]])).to be_nil
    end
  end

  describe "#curl_response_follow_redirections" do
    it "returns the original URL when there are no location headers" do
      expect(
        curl_response_follow_redirections(
          [response_hash[:ok]],
          "https://brew.sh/test1/test2",
        ),
      ).to eq("https://brew.sh/test1/test2")
    end

    it "returns the URL relative to base when locations are relative" do
      expect(
        curl_response_follow_redirections(
          [response_hash[:redirection_root_relative], response_hash[:ok]],
          "https://brew.sh/test1/test2",
        ),
      ).to eq("https://brew.sh/example/")

      expect(
        curl_response_follow_redirections(
          [response_hash[:redirection_parent_relative], response_hash[:ok]],
          "https://brew.sh/test1/test2",
        ),
      ).to eq("https://brew.sh/test1/example/")

      expect(
        curl_response_follow_redirections(
          [
            response_hash[:redirection_parent_relative],
            response_hash[:redirection_parent_relative],
            response_hash[:ok],
          ],
          "https://brew.sh/test1/test2",
        ),
      ).to eq("https://brew.sh/test1/example/example/")
    end

    it "returns new base when there are absolute location(s)" do
      expect(
        curl_response_follow_redirections(
          [response_hash[:redirection], response_hash[:ok]],
          "https://brew.sh/test1/test2",
        ),
      ).to eq(location_urls[0])

      expect(
        curl_response_follow_redirections(
          [response_hash[:redirection], response_hash[:redirection_parent_relative], response_hash[:ok]],
          "https://brew.sh/test1/test2",
        ),
      ).to eq("#{location_urls[0]}example/")
    end
  end
end
