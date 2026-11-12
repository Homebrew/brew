# typed: true
# frozen_string_literal: true

require "vulns/platform_independence"

RSpec.describe Homebrew::Vulns::PlatformIndependence do
  def independent?(body)
    described_class.source?("class Example < Formula\n#{body}\nend\n")
  end

  it "accepts literal matcher metadata and deferred installation and test code" do
    expect(independent?(<<~'RUBY')).to be true
      include Language::Python::Virtualenv
      desc "Example"
      homepage "https://example.test"
      url "https://example.test/example-2.0.tar.gz", tag: "v2.0"
      version "2.0"
      revision 1
      version_scheme 1
      sha256 "abc"
      license any_of: ["MIT", "BSD-2-Clause"]
      head "https://example.test/example.git", branch: "main"
      depends_on "python@3.14"
      uses_from_macos "libffi"
      pypi_packages exclude_packages: %w[certifi]
      bottle do
        sha256 cellar: :any_skip_relocation, arm64_tahoe: "abc", x86_64_linux: "def"
        rebuild 1
      end
      stable do
        mirror "https://mirror.test/example-2.0.tar.gz"
        resource "certifi" do
          url "https://example.test/certifi-1.0.tar.gz"
          patch do
            url "https://example.test/fix.diff"
            sha256 "def"
            resolves "CVE-2024-1234"
          end
        end
      end
      def install
        system "make", OS.mac? ? "mac" : "linux"
      end
      test do
        system "#{bin}/example", "--version"
      end
    RUBY
  end

  it "rejects on_linux resources" do
    expect(independent?(<<~RUBY)).to be false
      on_linux do
        resource "dep" do
          url "https://example.test/dep-1.0.tar.gz"
        end
      end
    RUBY
  end

  it "rejects on_macos resources" do
    expect(independent?(<<~RUBY)).to be false
      on_macos do
        resource "dep" do
          url "https://example.test/dep-1.0.tar.gz"
        end
      end
    RUBY
  end

  it "rejects class-level OS conditionals" do
    expect(independent?(<<~RUBY)).to be false
      if OS.mac?
        url "https://example.test/mac-1.0.tar.gz"
      end
    RUBY
  end

  it "rejects hardware-selected values" do
    expect(independent?(<<~RUBY)).to be false
      url Hardware::CPU.arm? ? "arm" : "intel"
    RUBY
  end

  it "rejects helper-derived metadata" do
    expect(independent?(<<~RUBY)).to be false
      def self.archive
        "https://example.test/dep-1.0.tar.gz"
      end
      url archive
    RUBY
  end

  it "rejects interpolated resource URLs" do
    expect(independent?(<<~'RUBY')).to be false
      resource "dep" do
        url "https://example.test/dep-#{version}.tar.gz"
      end
    RUBY
  end

  it "rejects macOS-version DSL" do
    expect(independent?(<<~RUBY)).to be false
      on_sonoma :or_newer do
        depends_on "dep"
      end
    RUBY
  end

  it "rejects on_system DSL" do
    expect(independent?(<<~RUBY)).to be false
      on_system :linux, macos: :sonoma do
        depends_on "dep"
      end
    RUBY
  end

  it "rejects unknown DSL" do
    expect(independent?(<<~RUBY)).to be false
      mystery "literal"
    RUBY
  end

  it "rejects constants used as metadata" do
    expect(independent?(<<~RUBY)).to be false
      ARCHIVE = "https://example.test/dep-1.0.tar.gz"
      url ARCHIVE
    RUBY
  end

  it "rejects boolean-derived values" do
    expect(independent?(<<~RUBY)).to be false
      url ENV["SOURCE"] || "https://example.test/dep-1.0.tar.gz"
    RUBY
  end

  it "rejects conditional patch annotations" do
    expect(independent?(<<~RUBY)).to be false
      patch do
        url "https://example.test/fix.diff"
        resolves "CVE-2024-1234" if OS.mac?
      end
    RUBY
  end

  it "rejects custom metadata methods" do
    expect(independent?(<<~RUBY)).to be false
      def resources
        []
      end
    RUBY
  end

  it "rejects unknown mixins" do
    expect(independent?(<<~RUBY)).to be false
      include CustomHelpers
    RUBY
  end

  it "rejects executable argument splats" do
    expect(independent?(<<~RUBY)).to be false
      depends_on(*packages)
    RUBY
  end

  it "rejects metaprogramming" do
    expect(independent?(<<~'RUBY')).to be false
      class_eval "url \"x\""
    RUBY
  end

  it "rejects execution inside bottle blocks" do
    expect(independent?(<<~RUBY)).to be false
      bottle do
        Formula.class_eval { def version; "0"; end }
      end
    RUBY
  end

  it "rejects unparsable source" do
    expect(described_class.source?("class Example < Formula")).to be false
  end

  it "rejects statements outside the formula class" do
    expect(described_class.source?("require 'helper'\nclass Example < Formula; end")).to be false
  end

  it "falls back when the current source cannot be read" do
    current = formula("example") do
      T.bind(self, T.class_of(Formula))
      url "https://example.test/example-1.0.tar.gz"
    end
    allow(current.path).to receive(:stat).and_raise(Errno::ENOENT)

    expect(described_class.formula?(current)).to be false
  end

  it "reuses the source already loaded for the formula" do
    path = mktmpdir/"example.rb"
    path.write <<~RUBY
      class Example < Formula
        url "https://example.test/example-1.0.tar.gz"
      end
    RUBY
    current = Formulary.from_path(path)
    expect(current.path).not_to receive(:read)

    2.times { described_class.formula?(current) }
  end
end
