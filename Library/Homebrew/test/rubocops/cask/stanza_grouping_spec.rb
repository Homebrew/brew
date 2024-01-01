# frozen_string_literal: true

require "rubocops/rubocop-cask"

describe RuboCop::Cop::Cask::StanzaGrouping, :config do
  it "accepts a sole stanza" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        version :latest
      end
    CASK
  end

  it "accepts correctly grouped stanzas" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "accepts correctly grouped stanzas and variable assignments" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "reports an offense when a stanza is grouped incorrectly" do
    expect_offense <<~CASK
      cask 'foo' do
        version :latest

      ^{} stanzas within the same group should have no lines between them
        sha256 :no_check
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "reports an offense for an incorrectly grouped `arch` stanza" do
    expect_offense <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"
        version :latest
      ^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        sha256 :no_check
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"

        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "reports an offense for an incorrectly grouped variable assignment" do
    expect_offense <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        version :latest
      ^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        sha256 :no_check
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

        version :latest
        sha256 :no_check
      end
    CASK
  end

  it "reports an offense for multiple incorrectly grouped stanzas" do
    expect_offense <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
        url 'https://foo.brew.sh/foo.zip'
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line

      ^{} stanzas within the same group should have no lines between them
        name 'Foo'

      ^{} stanzas within the same group should have no lines between them
        homepage 'https://foo.brew.sh'

        app 'Foo.app'
        uninstall :quit => 'com.example.foo',
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
                  :kext => 'com.example.foo.kextextension'
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check

        url 'https://foo.brew.sh/foo.zip'
        name 'Foo'
        homepage 'https://foo.brew.sh'

        app 'Foo.app'

        uninstall :quit => 'com.example.foo',
                  :kext => 'com.example.foo.kextextension'
      end
    CASK
  end

  it "reports an offense for multiple incorrectly grouped stanzas and variable assignments" do
    expect_offense <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

      ^{} stanzas within the same group should have no lines between them
        platform = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        version :latest
      ^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        sha256 :no_check

        url 'https://foo.brew.sh/foo.zip'

      ^{} stanzas within the same group should have no lines between them
        name 'Foo'

      ^{} stanzas within the same group should have no lines between them
        homepage 'https://foo.brew.sh'

        app 'Foo.app'
        uninstall :quit => 'com.example.foo',
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
                  :kext => 'com.example.foo.kextextension'
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        platform = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

        version :latest
        sha256 :no_check

        url 'https://foo.brew.sh/foo.zip'
        name 'Foo'
        homepage 'https://foo.brew.sh'

        app 'Foo.app'

        uninstall :quit => 'com.example.foo',
                  :kext => 'com.example.foo.kextextension'
      end
    CASK
  end

  shared_examples "caveats" do
    it "reports an offense for an incorrectly grouped `caveats` stanza" do
      # Indent all except the first line.
      interpolated_caveats = caveats.strip

      expect_offense <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check
          url 'https://foo.brew.sh/foo.zip'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
          name 'Foo'
          app 'Foo.app'
        ^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
          #{interpolated_caveats}
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

  context "when `caveats` is a one-line string" do
    let(:caveats) do
      <<~CAVEATS
          caveats 'This is a one-line caveat.'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
      CAVEATS
    end

    include_examples "caveats"
  end

  context "when `caveats` is a heredoc" do
    let(:caveats) do
      <<~CAVEATS
          caveats <<~EOS
        ^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
            This is a multiline caveat.

            Let's hope it doesn't cause any problems!
          EOS
      CAVEATS
    end

    include_examples "caveats"
  end

  context "when `caveats` is a block" do
    let(:caveats) do
      <<~CAVEATS
          caveats do
        ^^^^^^^^^^^^ stanza groups should be separated by a single empty line
            puts 'This is a multiline caveat.'

            puts "Let's hope it doesn't cause any problems!"
          end
      CAVEATS
    end

    include_examples "caveats"
  end

  it "reports an offense for an incorrectly grouped `postflight` stanza" do
    expect_offense <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
        url 'https://foo.brew.sh/foo.zip'
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        name 'Foo'
        app 'Foo.app'
      ^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        postflight do
      ^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
          puts 'We have liftoff!'
        end
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

  it "reports an offense for incorrectly grouped comments" do
    expect_offense <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check
        # comment with an empty line between
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line

        # comment directly above
        postflight do
          puts 'We have liftoff!'
        end
        url 'https://foo.brew.sh/foo.zip'
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        name 'Foo'
        app 'Foo.app'
      ^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        version :latest
        sha256 :no_check

        # comment with an empty line between

        # comment directly above
        postflight do
          puts 'We have liftoff!'
        end

        url 'https://foo.brew.sh/foo.zip'
        name 'Foo'

        app 'Foo.app'
      end
    CASK
  end

  it "reports an offense for incorrectly grouped comments and variable assignments" do
    expect_offense <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        # comment with an empty line between
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        version :latest
        sha256 :no_check

        # comment directly above
        postflight do
          puts 'We have liftoff!'
        end
        url 'https://foo.brew.sh/foo.zip'
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        name 'Foo'
        app 'Foo.app'
      ^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "arm64", intel: "x86_64"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

        # comment with an empty line between
        version :latest
        sha256 :no_check

        # comment directly above
        postflight do
          puts 'We have liftoff!'
        end

        url 'https://foo.brew.sh/foo.zip'
        name 'Foo'

        app 'Foo.app'
      end
    CASK
  end

  it "reports an offense for incorrectly grouped stanzas in `on_*` blocks" do
    expect_offense <<~CASK
      cask 'foo' do
        on_arm do
          version "1.0.2"

      ^{} stanzas within the same group should have no lines between them
          sha256 :no_check
        end
        on_intel do
          version "0.9.8"
          sha256 :no_check
          url "https://foo.brew.sh/foo-intel.zip"
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ stanza groups should be separated by a single empty line
        end
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        on_arm do
          version "1.0.2"
          sha256 :no_check
        end
        on_intel do
          version "0.9.8"
          sha256 :no_check

          url "https://foo.brew.sh/foo-intel.zip"
        end
      end
    CASK
  end

  it "reports an offense for incorrectly grouped stanzas with comments in `on_*` blocks" do
    expect_offense <<~CASK
      cask 'foo' do
        on_arm do
          version "1.0.2"

      ^{} stanzas within the same group should have no lines between them
          sha256 :no_check # comment on same line
        end
        on_intel do
          version "0.9.8"
          sha256 :no_check
        end
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        on_arm do
          version "1.0.2"
          sha256 :no_check # comment on same line
        end
        on_intel do
          version "0.9.8"
          sha256 :no_check
        end
      end
    CASK
  end
end
