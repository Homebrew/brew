# frozen_string_literal: true

# These tests assume the needed SDKs are correctly installed, i.e. `brew doctor` passes.
# The CLT version installed should be the latest available for the running OS.
# The tests do not check other OS versions beyond than the one the tests are being run on.
#
# It is not possible to automatically check the following libraries for version updates:
#
# - libedit (incorrect LIBEDIT_MAJOR/MINOR in histedit.h)
# - uuid (not a standalone library)
#
# Additionally, libffi version detection cannot be performed on systems running Mojave or earlier.
#
# For indeterminable cases, consult https://opensource.apple.com for the version used.
describe "pkg-config", :needs_ci do
  def pc_version(library)
    path = HOMEBREW_LIBRARY_PATH/"os/mac/pkgconfig/#{MacOS.version}/#{library}.pc"
    version = File.foreach(path)
                  .lazy
                  .grep(/^Version:\s*?(.+)$/) { Regexp.last_match(1) }
                  .first
                  .strip
    if (match = version.match(/^\${(.+?)}$/))
      version = File.foreach(path)
                    .lazy
                    .grep(/^#{match.captures.first}\s*?=\s*?(.+)$/) { Regexp.last_match(1) }
                    .first
                    .strip
    end
    version
  end

  let(:sdk) { MacOS.sdk_path_if_needed }

  it "returns the correct version for expat" do
    version = File.foreach("#{sdk}/usr/include/expat.h")
                  .lazy
                  .grep(/^#define XML_(MAJOR|MINOR|MICRO)_VERSION (\d+)$/) do
                    { Regexp.last_match(1).downcase => Regexp.last_match(2) }
                  end
                  .reduce(:merge!)
    version = "#{version["major"]}.#{version["minor"]}.#{version["micro"]}"

    expect(pc_version("expat")).to eq(version)
  end

  it "returns the correct version for libcurl" do
    version = File.foreach("#{sdk}/usr/include/curl/curlver.h")
                  .lazy
                  .grep(/^#define LIBCURL_VERSION "(.*?)"$/) { Regexp.last_match(1) }
                  .first

    expect(pc_version("libcurl")).to eq(version)
  end

  it "returns the correct version for libexslt" do
    version = File.foreach("#{sdk}/usr/include/libexslt/exsltconfig.h")
                  .lazy
                  .grep(/^#define LIBEXSLT_VERSION (\d+)$/) { Regexp.last_match(1) }
                  .first
                  .rjust(6, "0")
    version = "#{version[-6..-5].to_i}.#{version[-4..-3].to_i}.#{version[-2..].to_i}"

    expect(pc_version("libexslt")).to eq(version)
  end

  it "returns the correct version for libffi" do
    version = File.foreach("#{sdk}/usr/include/ffi/ffi.h")
                  .lazy
                  .grep(/^\s*libffi (\S+)\s+(?:- Copyright |$)/) { Regexp.last_match(1) }
                  .first

    skip "Cannot detect system libffi version." if version == "PyOBJC"

    expect(pc_version("libffi")).to eq(version)
  end

  it "returns the correct version for libxml-2.0" do
    version = File.foreach("#{sdk}/usr/include/libxml2/libxml/xmlversion.h")
                  .lazy
                  .grep(/^#define LIBXML_DOTTED_VERSION "(.*?)"$/) { Regexp.last_match(1) }
                  .first

    expect(pc_version("libxml-2.0")).to eq(version)
  end

  it "returns the correct version for libxslt" do
    version = File.foreach("#{sdk}/usr/include/libxslt/xsltconfig.h")
                  .lazy
                  .grep(/^#define LIBXSLT_DOTTED_VERSION "(.*?)"$/) { Regexp.last_match(1) }
                  .first

    expect(pc_version("libxslt")).to eq(version)
  end

  it "returns the correct version for ncurses" do
    version = File.foreach("#{sdk}/usr/include/ncurses.h")
                  .lazy
                  .grep(/^#define NCURSES_VERSION_(MAJOR|MINOR|PATCH) (\d+)$/) do
                    { Regexp.last_match(1).downcase => Regexp.last_match(2) }
                  end
                  .reduce(:merge!)
    version = "#{version["major"]}.#{version["minor"]}.#{version["patch"]}"

    expect(pc_version("ncurses")).to eq(version)
    expect(pc_version("ncursesw")).to eq(version)
  end

  it "returns the correct version for sqlite3" do
    version = File.foreach("#{sdk}/usr/include/sqlite3.h")
                  .lazy
                  .grep(/^#define SQLITE_VERSION\s+?"(.*?)"$/) { Regexp.last_match(1) }
                  .first

    expect(pc_version("sqlite3")).to eq(version)
  end

  it "returns the correct version for zlib" do
    version = File.foreach("#{sdk}/usr/include/zlib.h")
                  .lazy
                  .grep(/^#define ZLIB_VERSION "(.*?)"$/) { Regexp.last_match(1) }
                  .first

    expect(pc_version("zlib")).to eq(version)
  end
end
