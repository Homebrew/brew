# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::StanzaOrder, :config do
  it "accepts a sole stanza" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        version :latest
      end
    CASK
  end

  it "accepts when all stanzas are in order" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        arch arm: "arm", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        version :latest
        sha256 :no_check
        foo = "bar"
      end
    CASK
  end

  it "reports an offense when stanzas are out of order" do
    expect_offense <<~CASK
      cask 'foo' do
        sha256 :no_check
        ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
        version :latest
        ^^^^^^^^^^^^^^^ `version` stanza out of order
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "reports an offense when an `arch` stanza is out of order" do
    expect_offense <<~CASK
      cask 'foo' do
        version :latest
        ^^^^^^^^^^^^^^^ `version` stanza out of order
        sha256 :no_check
        ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
        arch arm: "arm", intel: "x86_64"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `arch` stanza out of order
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "arm", intel: "x86_64"
        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "reports an offense when an `on_arch_conditional` variable assignment is out of order" do
    expect_offense <<~CASK
      cask 'foo' do
        arch arm: "arm", intel: "x86_64"
        sha256 :no_check
        ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
        version :latest
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `on_arch_conditional` stanza out of order
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "arm", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "reports an offense when an `on_arch_conditional` variable assignment is above an `arch` stanza" do
    expect_offense <<~CASK
      cask 'foo' do
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `on_arch_conditional` stanza out of order
        arch arm: "arm", intel: "x86_64"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `arch` stanza out of order
        version :latest
        sha256 :no_check
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "arm", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "reports an offense when multiple stanzas are out of order" do
    expect_offense <<~CASK
      cask 'foo' do
        url 'https://foo.brew.sh/foo.zip'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `url` stanza out of order
        uninstall :quit => 'com.example.foo',
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `uninstall` stanza out of order
                  :kext => 'com.example.foo.kext'
        version :latest
        ^^^^^^^^^^^^^^^ `version` stanza out of order
        app 'Foo.app'
        sha256 :no_check
        ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
        url 'https://foo.brew.sh/foo.zip'
        app 'Foo.app'
        uninstall :quit => 'com.example.foo',
                  :kext => 'com.example.foo.kext'
      end
    CASK
  end

  it "does not reorder multiple stanzas of the same type" do
    expect_offense <<~CASK
      cask 'foo' do
        name 'Foo'
        ^^^^^^^^^^ `name` stanza out of order
        url 'https://foo.brew.sh/foo.zip'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `url` stanza out of order
        name 'FancyFoo'
        ^^^^^^^^^^^^^^^ `name` stanza out of order
        version :latest
        ^^^^^^^^^^^^^^^ `version` stanza out of order
        app 'Foo.app'
        ^^^^^^^^^^^^^ `app` stanza out of order
        sha256 :no_check
        ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
        name 'FunkyFoo'
        ^^^^^^^^^^^^^^^ `name` stanza out of order
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
        url 'https://foo.brew.sh/foo.zip'
        name 'Foo'
        name 'FancyFoo'
        name 'FunkyFoo'
        app 'Foo.app'
      end
    CASK
  end

  it "keeps associated comments when auto-correcting" do
    expect_offense <<~CASK
      cask 'foo' do
        version :latest
        # comment with an empty line between

        # comment directly above
        postflight do
        ^^^^^^^^^^^^^ `postflight` stanza out of order
          puts 'We have liftoff!'
        end
        sha256 :no_check # comment on same line
        ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
      end
    CASK

    expect_correction <<~CASK, loop: false
      cask 'foo' do
        version :latest
        sha256 :no_check # comment on same line
        # comment with an empty line between

        # comment directly above
        postflight do
          puts 'We have liftoff!'
        end
      end
    CASK
  end

  it "reports an offense when an `on_arch_conditional` variable assignment with a comment is out of order" do
    expect_offense <<~CASK
      cask 'foo' do
        version :latest
        ^^^^^^^^^^^^^^^ `version` stanza out of order
        sha256 :no_check
        ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
        # comment with an empty line between

        # comment directly above
        postflight do
        ^^^^^^^^^^^^^ `postflight` stanza out of order
          puts 'We have liftoff!'
        end
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin" # comment on same line
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `on_arch_conditional` stanza out of order
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin" # comment on same line
        version :latest
        sha256 :no_check
        # comment with an empty line between

        # comment directly above
        postflight do
          puts 'We have liftoff!'
        end
      end
    CASK
  end

  shared_examples "caveats" do
    it "reports an offense when a `caveats` stanza is out of order" do
      # Indent all except the first line.
      interpolated_caveats = caveats.lines.map { |l| "  #{l}" }.join.strip

      expect_offense <<~CASK
        cask 'foo' do
          name 'Foo'
          ^^^^^^^^^^ `name` stanza out of order
          url 'https://foo.brew.sh/foo.zip'
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `url` stanza out of order
          #{interpolated_caveats}
          version :latest
          ^^^^^^^^^^^^^^^ `version` stanza out of order
          app 'Foo.app'
          sha256 :no_check
          ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
        end
      CASK

      # Remove offense annotations.
      corrected_caveats = interpolated_caveats.gsub(/\n\s*\^+\s+.*$/, "")

      expect_correction <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check
          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'
          app 'Foo.app'
          #{corrected_caveats}
        end
      CASK
    end
  end

  context "when caveats is a one-line string" do
    let(:caveats) do
      <<~CAVEATS
        caveats 'This is a one-line caveat.'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `caveats` stanza out of order
      CAVEATS
    end

    include_examples "caveats"
  end

  context "when caveats is a heredoc" do
    let(:caveats) do
      <<~CAVEATS
        caveats <<~EOS
        ^^^^^^^^^^^^^^ `caveats` stanza out of order
          This is a multiline caveat.

          Let's hope it doesn't cause any problems!
        EOS
      CAVEATS
    end

    include_examples "caveats"
  end

  context "when caveats is a block" do
    let(:caveats) do
      <<~CAVEATS
        caveats do
        ^^^^^^^^^^ `caveats` stanza out of order
          puts 'This is a multiline caveat.'

          puts "Let's hope it doesn't cause any problems!"
        end
      CAVEATS
    end

    include_examples "caveats"
  end

  it "reports an offense when the `postflight` stanza is out of order" do
    expect_offense <<~CASK
      cask 'foo' do
        name 'Foo'
        ^^^^^^^^^^ `name` stanza out of order
        url 'https://foo.brew.sh/foo.zip'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `url` stanza out of order
        postflight do
        ^^^^^^^^^^^^^ `postflight` stanza out of order
          puts 'We have liftoff!'
        end
        version :latest
        ^^^^^^^^^^^^^^^ `version` stanza out of order
        app 'Foo.app'
        sha256 :no_check
        ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
        url 'https://foo.brew.sh/foo.zip'
        name 'Foo'
        app 'Foo.app'
        postflight do
          puts 'We have liftoff!'
        end
      end
    CASK
  end

  it "supports `on_arch` blocks and their contents" do
    expect_offense <<~CASK
      cask 'foo' do
        on_intel do
        ^^^^^^^^^^^ `on_intel` stanza out of order
          url "https://foo.brew.sh/foo-intel.zip"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `url` stanza out of order

          version :latest
          ^^^^^^^^^^^^^^^ `version` stanza out of order
          sha256 :no_check
          ^^^^^^^^^^^^^^^^ `sha256` stanza out of order
        end
        on_arm do
        ^^^^^^^^^ `on_arm` stanza out of order
          version :latest
          sha256 :no_check

          url "https://foo.brew.sh/foo-arm.zip"
        end
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        on_arm do
          version :latest
          sha256 :no_check

          url "https://foo.brew.sh/foo-arm.zip"
        end
        on_intel do
          version :latest

          sha256 :no_check
          url "https://foo.brew.sh/foo-intel.zip"
        end
      end
    CASK
  end

  it "registers an offense when `on_os` stanzas and their contents are out of order" do
    expect_offense <<~CASK
      cask "foo" do
        on_ventura do
        ^^^^^^^^^^^^^ `on_ventura` stanza out of order
          sha256 "abc123"
          ^^^^^^^^^^^^^^^ `sha256` stanza out of order
          version :latest
          ^^^^^^^^^^^^^^^ `version` stanza out of order
          url "https://foo.brew.sh/foo-ventura.zip"
        end
        on_catalina do
          sha256 "def456"
          ^^^^^^^^^^^^^^^ `sha256` stanza out of order
          version "0.7"
          ^^^^^^^^^^^^^ `version` stanza out of order
          url "https://foo.brew.sh/foo-catalina.zip"
        end
        on_mojave do
        ^^^^^^^^^^^^ `on_mojave` stanza out of order
          version :latest
          sha256 "ghi789"
          url "https://foo.brew.sh/foo-mojave.zip"
        end
        on_big_sur do
        ^^^^^^^^^^^^^ `on_big_sur` stanza out of order
          sha256 "jkl012"
          ^^^^^^^^^^^^^^^ `sha256` stanza out of order
          version :latest
          ^^^^^^^^^^^^^^^ `version` stanza out of order

          url "https://foo.brew.sh/foo-big-sur.zip"
        end
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        on_mojave do
          version :latest
          sha256 "ghi789"
          url "https://foo.brew.sh/foo-mojave.zip"
        end
        on_catalina do
          version "0.7"
          sha256 "def456"
          url "https://foo.brew.sh/foo-catalina.zip"
        end
        on_big_sur do
          version :latest
          sha256 "jkl012"

          url "https://foo.brew.sh/foo-big-sur.zip"
        end
        on_ventura do
          version :latest
          sha256 "abc123"
          url "https://foo.brew.sh/foo-ventura.zip"
        end
      end
    CASK
  end
end
