# typed: true
# frozen_string_literal: true

require "rubocops/install_steps_source_independence"

RSpec.describe RuboCop::Cop::Homebrew::InstallStepsSourceIndependence, :config do
  it "rejects formula source lookups" do
    expect_offense <<~RUBY
      Formula["foo"]
      ^^^^^^^^^^^^^^ Install-step runners must use bottled files and API context without loading formula source or resources.
      Formulary.factory("foo")
      ^^^^^^^^^^^^^^^^^^^^^^^^ Install-step runners must use bottled files and API context without loading formula source or resources.
      formula_class = Formula
                      ^^^^^^^ Install-step runners must use bottled files and API context without loading formula source or resources.
    RUBY
  end

  it "rejects formula resources" do
    expect_offense <<~RUBY
      context.resource("setuptools")
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Install-step runners must use bottled files and API context without loading formula source or resources.
      Resource.new("pip")
      ^^^^^^^^^^^^^^^^^^^ Install-step runners must use bottled files and API context without loading formula source or resources.
    RUBY
  end

  it "rejects direct downloads" do
    source = 'Utils::Curl.curl_download("https://example.com/input")'
    expect_offense(<<~RUBY, source:)
      #{source}
      ^{source} Install-step runners must use bottled files and API context without loading formula source or resources.
    RUBY

    source = 'URI.open("https://example.com/input")'
    expect_offense(<<~RUBY, source:)
      #{source}
      ^{source} Install-step runners must use bottled files and API context without loading formula source or resources.
    RUBY
  end

  it "accepts bottled paths and archives" do
    expect_no_offenses <<~RUBY
      archive = context_path("libexec")/"post-install-resources/input.tar.gz"
      UnpackStrategy.detect(archive).extract(to: temporary_path)
      Utils::Path.formula_opt_bin("glib")/"gio-querymodules"
    RUBY
  end
end
