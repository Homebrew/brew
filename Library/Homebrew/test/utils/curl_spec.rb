# typed: true
# frozen_string_literal: true

require "utils/curl"

RSpec.describe "Utils::Curl" do
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

    details[:normal][:ok] = details[:normal][:no_cookie].deep_dup
    details[:normal][:ok][:status_code] = "200"

    details[:normal][:single_cookie] = details[:normal][:no_cookie].deep_dup
    details[:normal][:single_cookie][:headers]["set-cookie"] = "a_cookie=for_testing"

    details[:normal][:multiple_cookies] = details[:normal][:no_cookie].deep_dup
    details[:normal][:multiple_cookies][:headers]["set-cookie"] = [
      "first_cookie=for_testing",
      "last_cookie=also_for_testing",
    ]

    details[:normal][:blank_headers] = details[:normal][:no_cookie].deep_dup
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

    details[:cloudflare][:multiple_cookies] = details[:cloudflare][:single_cookie].deep_dup
    details[:cloudflare][:multiple_cookies][:headers]["set-cookie"] = [
      "first_cookie=for_testing",
      "__cf_bm=abcdef0123456789; path=/; expires=Thu, 28-Apr-22 18:38:40 GMT; domain=www.example.com; HttpOnly; " \
      "Secure; SameSite=None",
      "last_cookie=also_for_testing",
    ]

    details[:cloudflare][:no_server] = details[:cloudflare][:single_cookie].deep_dup
    details[:cloudflare][:no_server][:headers].delete("server")

    details[:cloudflare][:wrong_server] = details[:cloudflare][:single_cookie].deep_dup
    details[:cloudflare][:wrong_server][:headers]["server"] = "nginx 1.2.3"

    # TODO: Make the Incapsula test data more realistic once we can find an
    #       example website to reference.
    details[:incapsula][:single_cookie_visid_incap] = details[:normal][:no_cookie].deep_dup
    details[:incapsula][:single_cookie_visid_incap][:headers]["set-cookie"] = "visid_incap_something=something"

    details[:incapsula][:single_cookie_incap_ses] = details[:normal][:no_cookie].deep_dup
    details[:incapsula][:single_cookie_incap_ses][:headers]["set-cookie"] = "incap_ses_something=something"

    details[:incapsula][:multiple_cookies_visid_incap] = details[:normal][:no_cookie].deep_dup
    details[:incapsula][:multiple_cookies_visid_incap][:headers]["set-cookie"] = [
      "first_cookie=for_testing",
      "visid_incap_something=something",
      "last_cookie=also_for_testing",
    ]

    details[:incapsula][:multiple_cookies_incap_ses] = details[:normal][:no_cookie].deep_dup
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

    response_hash[:ok_no_status_text] = response_hash[:ok].deep_dup
    response_hash[:ok_no_status_text].delete(:status_text)

    response_hash[:ok_blank_header_value] = response_hash[:ok].deep_dup
    response_hash[:ok_blank_header_value][:headers]["range"] = ""

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

    response_text[:ok_no_status_text] = response_text[:ok].sub(" #{response_hash[:ok][:status_text]}", "")
    response_text[:ok_blank_header_name] = response_text[:ok].sub(
      "#{response_hash[:ok][:headers]["date"]}\r\n",
      "#{response_hash[:ok][:headers]["date"]}\r\n: Test\r\n",
    )
    response_text[:ok_blank_header_value] = response_text[:ok].sub(
      "#{response_hash[:ok][:headers]["date"]}\r\n",
      "#{response_hash[:ok][:headers]["date"]}\r\nRange:\r\n",
    )

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

    body[:default] = <<~HTML
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
    HTML

    body[:with_carriage_returns] = body[:default].sub("<html>\n", "<html>\r\n\r\n")

    body[:with_http_status_line] = body[:default].sub("<html>", "HTTP/1.1 200\r\n<html>")

    body
  end

  describe "::curl_executable" do
    it "returns HOMEBREW_BREWED_CURL_PATH when `use_homebrew_curl` is `true`" do
      expect(curl_executable(use_homebrew_curl: true)).to eq(HOMEBREW_BREWED_CURL_PATH)
    end

    it "returns curl shim path when `use_homebrew_curl` is `false` or omitted" do
      curl_shim_path = HOMEBREW_SHIMS_PATH/"shared/curl"
      expect(curl_executable(use_homebrew_curl: false)).to eq(curl_shim_path)
      expect(curl_executable).to eq(curl_shim_path)
    end
  end

  describe "::curl_path" do
    it "returns a curl path string" do
      expect(curl_path).to match(%r{[^/]+(?:/[^/]+)*})
    end
  end

  describe "::curl_args" do
    include Context

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

    it "uses `--max-time` when `:max_time` is Numeric" do
      expect(curl_args(*args, max_time: 123).join(" ")).to include("--max-time 123")
      expect(curl_args(*args, max_time: 123.4).join(" ")).to include("--max-time 123.4")
      expect(curl_args(*args, max_time: 123.4567).join(" ")).to include("--max-time 123.457")
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

    it "uses `--retry-max-time` when `:retry_max_time` is Numeric" do
      expect(curl_args(*args, retry_max_time: 123).join(" ")).to include("--retry-max-time 123")
      expect(curl_args(*args, retry_max_time: 123.4).join(" ")).to include("--retry-max-time 123")
    end

    it "uses `--show-error` when :show_error is `true`" do
      expect(curl_args(*args, show_error: true)).to include("--show-error")
      expect(curl_args(*args, show_error: false)).not_to include("--show-error")
    end

    it "uses `--cookie` with argument when :cookies is present" do
      cookies = { "cookie_key" => "cookie_value" }
      expect(curl_args(*args, cookies:).join(" "))
        .not_to include("--cookie #{File::NULL}")
      expect(curl_args(*args, cookies:).join(" "))
        .to include("--cookie cookie_key=cookie_value")
    end

    it "uses `--header` with argument when :header is present" do
      expect(curl_args(*args, header: "Accept: */*").join(" "))
        .to include("--header Accept: */*")
      expect(curl_args(*args, header: ["Accept: */*", "X-Requested-With: XMLHttpRequest"]).join(" "))
        .to include("--header Accept: */* --header X-Requested-With: XMLHttpRequest")
    end

    it "uses `--referer` when :referer is present" do
      expect(curl_args(*args, referer: "https://brew.sh").join(" ")).to include("--referer https://brew.sh")
    end

    it "doesn't use `--referer` when :referer is nil" do
      expect(curl_args(*args, referer: nil).join(" ")).not_to include("--referer")
    end

    it "omits `--user-agent` when `:user_agent` is `:curl`" do
      expect(curl_args(*args, user_agent: :curl).join(" ")).not_to include("--user-agent")
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
        .to raise_error(TypeError, ":user_agent must be :browser/:fake, :default, :curl, or a String")
      expect { curl_args(*args, user_agent: 123) }.to raise_error(TypeError)
    end

    it "uses `--fail` unless `:show_output` is `true`" do
      expect(curl_args(*args, show_output: false).join(" ")).to include("--fail")
      expect(curl_args(*args, show_output: nil).join(" ")).to include("--fail")
      expect(curl_args(*args).join(" ")).to include("--fail")
      expect(curl_args(*args, show_output: true).join(" ")).not_to include("--fail")
    end

    it "uses `--progress-bar` outside of a `--verbose` context" do
      expect(curl_args(*args).join(" ")).to include("--progress-bar")
      with_context verbose: true do
        expect(curl_args(*args).join(" ")).not_to include("--progress-bar")
      end
    end

    context "when `EnvConfig.curl_verbose?` is `true`" do
      before do
        allow(Homebrew::EnvConfig).to receive(:curl_verbose?).and_return(true)
      end

      it "uses `--verbose`" do
        expect(curl_args(*args).join(" ")).to include("--verbose")
      end
    end

    context "when `EnvConfig.curl_verbose?` is `false`" do
      before do
        allow(Homebrew::EnvConfig).to receive(:curl_verbose?).and_return(false)
      end

      it "doesn't use `--verbose`" do
        expect(curl_args(*args).join(" ")).not_to include("--verbose")
      end
    end

    context "when `$stdout.tty?` is `false`" do
      before do
        allow($stdout).to receive(:tty?).and_return(false)
      end

      it "uses `--silent`" do
        expect(curl_args(*args).join(" ")).to include("--silent")
      end
    end

    context "when `$stdout.tty?` is `true`" do
      before do
        allow($stdout).to receive(:tty?).and_return(true)
      end

      it "doesn't use `--silent` outside of a `--quiet` context" do
        with_context quiet: false do
          expect(curl_args(*args).join(" ")).not_to include("--silent")
        end

        with_context quiet: true do
          expect(curl_args(*args).join(" ")).to include("--silent")
        end
      end
    end
  end

  describe "::url_protected_by_cloudflare?" do
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

  describe "::url_protected_by_incapsula?" do
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

  describe "::curl_version" do
    it "returns a curl version string" do
      expect(curl_version).to match(/^v?\d+(?:\.\d+)+$/)
    end

    it "only runs the curl subprocess on the first call" do
      allow(self).to receive(:curl_path).and_return("/usr/bin/curl")
      expect(self).to receive(:curl_output).once.and_return(
        instance_double(SystemCommand::Result, stdout: "curl 8.7.1 (x86_64-apple-darwin)"),
      )
      2.times { expect(curl_version).to eq(Version.new("8.7.1")) }
    end
  end

  describe "::curl_supports_fail_with_body?" do
    it "returns `true` if curl version is 7.76.0 or higher" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(Version.new("7.76.0"))
      expect(curl_supports_fail_with_body?).to be(true)

      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(Version.new("7.76.1"))
      expect(curl_supports_fail_with_body?).to be(true)
    end

    it "returns `false` if curl version is lower than 7.76.0" do
      allow_any_instance_of(Utils::Curl).to receive(:curl_version).and_return(Version.new("7.75.0"))
      expect(curl_supports_fail_with_body?).to be(false)
    end
  end

  describe "::curl_supports_tls13?" do
    it "returns `true` if curl command is successful" do
      allow(SystemCommand).to receive(:quiet_system).and_return(true)
      expect(curl_supports_tls13?).to be(true)
    end

    it "returns `false` if curl command is not successful" do
      allow(SystemCommand).to receive(:quiet_system).and_return(false)
      expect(curl_supports_tls13?).to be(false)
    end
  end

  describe "::no_insecure_redirect_curl_args" do
    before do
      allow(Homebrew::EnvConfig).to receive(:no_insecure_redirect?).and_return(true)
    end

    it "only allows HTTPS redirects for redirect-following calls" do
      expect(no_insecure_redirect_curl_args(["--location", "http://example.com/example.tar.gz"]))
        .to eq(["--proto-redir", "=https", "--location", "http://example.com/example.tar.gz"])
    end

    it "drops custom redirect protocol arguments" do
      expect(no_insecure_redirect_curl_args(["--location", "--proto-redir", "=all",
                                             "https://example.com/example.tar.gz"]))
        .to eq(["--proto-redir", "=https", "--location", "https://example.com/example.tar.gz"])
    end

    it "drops custom redirect protocol arguments in assignment form" do
      expect(no_insecure_redirect_curl_args(["--location", "--proto-redir=all",
                                             "https://example.com/example.tar.gz"]))
        .to eq(["--proto-redir", "=https", "--location", "https://example.com/example.tar.gz"])
    end
  end

  describe "::curl_output" do
    it "enforces HTTPS redirects before running curl" do
      allow(Homebrew::EnvConfig).to receive(:no_insecure_redirect?).and_return(true)

      expect(self).to receive(:system_command).with(
        /curl/,
        hash_including(args: array_including("--proto-redir", "=https")),
      ).and_return(
        instance_double(SystemCommand::Result, success?: true, stdout: ""),
      )

      curl_output("--location", "https://example.com/example.tar.gz")
    end

    it "does not expand deferred environment placeholders" do
      ENV["HOMEBREW_PRIVATE_TOKEN"] = "glpat-secret"
      url = ENV.clear_sensitive_environment_for_eval! do
        "https://example.com/example.tar.gz?private_token=#{ENV.fetch("HOMEBREW_PRIVATE_TOKEN", nil)}"
      end

      expect(self).to receive(:system_command).with(
        /curl/,
        hash_including(args: array_including(url)),
      ).and_return(
        instance_double(SystemCommand::Result, success?: true, stdout: ""),
      )

      curl_output(url)
    end
  end

  describe "::curl_http_content_headers_and_checksum" do
    def curl_args_for(**options)
      args = T.let([], T::Array[String])
      allow(self).to receive(:curl_output) do |*arguments, **_options|
        args = arguments
        ["", "", instance_double(Process::Status, success?: false, exitstatus: 0)]
      end
      curl_http_content_headers_and_checksum("https://brew.sh/", **options)
      args
    end

    it "requests headers only when `head_only` is set" do
      expect(curl_args_for(head_only: true)).to include("--head")
    end

    it "does not write the body to a file when `head_only` is set" do
      expect(curl_args_for(head_only: true)).not_to include("--output")
    end

    it "does not combine `--dump-header` with `--head`" do
      expect(curl_args_for(head_only: true)).not_to include("--dump-header")
    end

    it "downloads the body when `head_only` is not set" do
      expect(curl_args_for(head_only: false)).to include("--output")
    end

    it "uses the last value of a header that was sent more than once" do
      output = "HTTP/1.1 301 Moved Permanently\r\n" \
               "Location: https://brew.sh/a\r\n" \
               "Location: https://brew.sh/b\r\n" \
               "\r\n" \
               "HTTP/1.1 200 OK\r\n" \
               "ETag: \"aaa\"\r\n" \
               "ETag: \"bbb\"\r\n" \
               "\r\n"
      allow(self).to receive(:curl_output)
        .and_return([output, "", instance_double(Process::Status, success?: false, exitstatus: 0)])

      response = curl_http_content_headers_and_checksum("https://brew.sh/", head_only: true)
      expect(response[:etag]).to eq("bbb")
      expect(response[:final_url]).to eq("https://brew.sh/b")
    end
  end

  describe "::curl_check_http_content" do
    let(:response) do
      {
        url:            "https://brew.sh/",
        final_url:      nil,
        exit_status:    0,
        status_code:    "200",
        headers:        {},
        etag:           nil,
        content_length: nil,
        file:           nil,
        file_hash:      nil,
        responses:      [],
      }
    end

    # Returns the recorded `head_only` of each fetch; responses are used in turn.
    def record_head_only(*responses)
      recorded = []
      allow(self).to receive(:curl_http_content_headers_and_checksum) do |_url, **options|
        recorded << options[:head_only]
        responses[[recorded.length - 1, responses.length - 1].min]
      end
      recorded
    end

    it "requests headers only for an HTTPS URL" do
      recorded = record_head_only(response)
      curl_check_http_content("https://brew.sh/", "homepage URL")
      expect(recorded).to eq([true])
    end

    it "downloads the body for an HTTP URL, which needs it for comparison" do
      recorded = record_head_only(response)
      curl_check_http_content("http://brew.sh/", "homepage URL")
      expect(recorded).to all(be_falsey)
    end

    it "retries as a `GET` when the server rejects `HEAD`" do
      recorded = record_head_only(response.merge(status_code: "405"), response)
      curl_check_http_content("https://brew.sh/", "homepage URL")
      expect(recorded).to eq([true, false])
    end

    it "reports the problem from the `GET` when the server rejects `HEAD`" do
      record_head_only(response.merge(status_code: "405"), response.merge(status_code: "500"))
      expect(curl_check_http_content("https://brew.sh/", "homepage URL"))
        .to include("HTTP status code 500")
    end

    # The request may have reached the server, so `HEAD` could be why it failed.
    test_each([28, 52, 56]) do |exit_status|
      it "retries as a `GET` when `HEAD` failed with exit status #{exit_status}" do
        recorded = record_head_only(response.merge(status_code: nil, exit_status:), response)
        curl_check_http_content("https://brew.sh/", "homepage URL")
        expect(recorded).to eq([true, false])
      end
    end

    # These happen before the request is sent.
    test_each([6, 7]) do |exit_status|
      it "does not retry as a `GET` when `HEAD` failed with exit status #{exit_status}" do
        recorded = record_head_only(response.merge(status_code: nil, exit_status:))
        curl_check_http_content("https://brew.sh/", "homepage URL")
        expect(recorded).to eq([true])
      end
    end

    it "still reports an unreachable URL when the `GET` retry also fails" do
      record_head_only(response.merge(status_code: nil, exit_status: 28))
      expect(curl_check_http_content("https://brew.sh/", "homepage URL"))
        .to include("is not reachable")
    end
  end

  describe "curl request deadlines" do
    let(:url) { "https://example.com/download.zip" }
    let(:start_time) { Time.at(1_700_000_000) }
    let(:result) do
      instance_double(SystemCommand::Result, success?: true, stdout: "HTTP/1.1 200 OK\r\n\r\n")
    end

    before do
      allow(Time).to receive(:now).and_return(start_time)
      allow(self).to receive(:curl_version).and_return(Version.new("8.10"))
    end

    context "when an unexpected EOF requires an HTTP/1.1 retry" do
      let(:retry_time) { start_time + 2 }

      before do
        allow(self).to receive(:system_command).and_return(
          instance_double(SystemCommand::Result, success?: false, exit_status: 56,
                                                status: instance_double(Process::Status, exitstatus: 56)),
        )
        allow(self).to receive(:curl_output).with("-V") do
          allow(Time).to receive(:now).and_return(retry_time)
          instance_double(SystemCommand::Result, stdout: "curl 7.59.0\nFeatures: HTTP2\n")
        end
      end

      it "passes the remaining timeout to the retry" do
        expect(self).to receive(:system_command).with(
          anything, hash_including(args: array_including("--http1.1"), timeout: 1)
        ).and_return(result)

        curl_with_workarounds(url, timeout: 3)
      end

      context "when the deadline has expired" do
        let(:retry_time) { start_time + 3 }

        it "raises instead of starting the retry" do
          expect { curl_with_workarounds(url, timeout: 3) }.to raise_error(Timeout::Error)
        end
      end
    end

    it "shares an explicit deadline between HEAD and its GET fallback" do
      timeouts = []
      allow(self).to receive(:curl_output) do |*_args, **options|
        timeouts << options[:timeout]
        allow(Time).to receive(:now).and_return(start_time + 2)
        result
      end

      curl_headers(url, wanted_headers: ["content-disposition"], deadline: start_time + 3)

      expect(timeouts).to eq([3, 1])
    end

    it "does not start the GET fallback after the deadline" do
      allow(self).to receive(:curl_output) do
        allow(Time).to receive(:now).and_return(start_time + 3)
        result
      end

      expect { curl_headers(url, wanted_headers: ["content-disposition"], deadline: start_time + 3) }
        .to raise_error(Timeout::Error)
    end

    it "subtracts the resume probe from the download timeout" do
      destination = mktmpdir/"download.zip"
      destination.write("partial")
      allow(self).to receive(:curl_headers)
        .with(any_args, wanted_headers: ["accept-ranges"], deadline: start_time + 3) do
          allow(Time).to receive(:now).and_return(start_time + 2)
          { responses: [{ headers: { "accept-ranges" => "bytes" } }] }
        end
      expect(self).to receive(:curl).with(any_args, timeout: 1)

      curl_download(url, to: destination, try_partial: true, timeout: 3)
    end
  end

  describe "::http_status_ok?" do
    it "returns `true` when `status` is 1xx or 2xx" do
      expect(http_status_ok?("200")).to be(true)
    end

    it "returns `false` when `status` is not 1xx or 2xx" do
      expect(http_status_ok?("301")).to be(false)
    end

    it "returns `false` when `status` is `nil`" do
      expect(http_status_ok?(nil)).to be(false)
    end
  end

  describe "::strip_progress_bar" do
    it "removes the percentage when other text is glued directly onto it" do
      glued = "############# 100.0%curl: (7) Failed to connect to example.com port 443: Couldn't connect to server"
      expected = "curl: (7) Failed to connect to example.com port 443: Couldn't connect to server"
      expect(strip_progress_bar(glued)).to eq(expected)
    end

    it "reduces a completed progress bar with nothing else on the line to an empty string" do
      expect(strip_progress_bar("############# 100.0%")).to eq("")
    end

    it "leaves plain curl diagnostics without a progress bar unchanged" do
      message = "curl: (6) Could not resolve host: example.com"
      expect(strip_progress_bar(message)).to eq(message)
    end

    it "only strips the line that actually has a progress bar" do
      glued = "Warning: retrying\n### 50.0%curl: (7) timeout"
      expect(strip_progress_bar(glued)).to eq("Warning: retrying\ncurl: (7) timeout")
    end
  end

  describe "::parse_curl_output" do
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

    it "errors if response count exceeds `max_iterations`" do
      expect do
        parse_curl_output(response_text[:redirections_to_ok], max_iterations: 1)
      end.to raise_error("Too many redirects (max = 1)")
    end
  end

  describe "::parse_curl_response" do
    it "returns a correct hash when given HTTP response text" do
      expect(parse_curl_response(response_text[:ok])).to eq(response_hash[:ok])
      expect(parse_curl_response(response_text[:ok_no_status_text])).to eq(response_hash[:ok_no_status_text])
      expect(parse_curl_response(response_text[:ok_blank_header_value])).to eq(response_hash[:ok_blank_header_value])
      expect(parse_curl_response(response_text[:redirection])).to eq(response_hash[:redirection])
      expect(parse_curl_response(response_text[:duplicate_header])).to eq(response_hash[:duplicate_header])
    end

    it "skips over response header lines with blank header name" do
      expect(parse_curl_response(response_text[:ok_blank_header_name])).to eq(response_hash[:ok])
    end

    it "returns an empty hash when given an empty string" do
      expect(parse_curl_response("")).to eq({})
    end
  end

  describe "::curl_response_last_location" do
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

    it "skips response hashes without a `:headers` value" do
      expect(curl_response_last_location([
        response_hash[:redirection],
        { status_code: "404", status_text: "Not Found" },
        response_hash[:ok],
      ])).to eq(response_hash[:redirection][:headers]["location"])
    end

    it "returns nil when the response hash doesn't contain a location header" do
      expect(curl_response_last_location([response_hash[:ok]])).to be_nil
    end

    it "uses the last location when the header was sent more than once" do
      duplicated = {
        status_code: "301",
        headers:     { "location" => ["https://brew.sh/a", "/b"] },
      }

      expect(curl_response_last_location([duplicated, response_hash[:ok]])).to eq("/b")
      expect(
        curl_response_last_location([duplicated, response_hash[:ok]], absolutize: true,
                                                                      base_url:   "https://brew.sh/test"),
      ).to eq("https://brew.sh/b")
    end
  end

  describe "::curl_response_follow_redirections" do
    it "returns the original URL when there are no location headers" do
      expect(
        curl_response_follow_redirections(
          [response_hash[:ok]],
          "https://brew.sh/test1/test2",
        ),
      ).to eq("https://brew.sh/test1/test2")
    end

    it "uses the last location when the header was sent more than once" do
      expect(
        curl_response_follow_redirections(
          [{ status_code: "301", headers: { "location" => ["/a", "/b"] } }, response_hash[:ok]],
          "https://brew.sh/test1/test2",
        ),
      ).to eq("https://brew.sh/b")
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

    it "skips response hashes without a `:headers` value" do
      expect(
        curl_response_follow_redirections(
          [
            response_hash[:redirection_root_relative],
            { status_code: "404", status_text: "Not Found" },
            response_hash[:ok],
          ],
          "https://brew.sh/test1/test2",
        ),
      ).to eq("https://brew.sh/example/")
    end
  end
end
