# frozen_string_literal: true

require "cask/audit"

RSpec.describe Cask::Audit, :cask do
  def include_msg?(problems, msg)
    if msg.is_a?(Regexp)
      Array(problems).any? { |problem| msg.match?(problem[:message]) }
    else
      Array(problems).any? { |problem| problem[:message] == msg }
    end
  end

  def passed?(audit)
    !audit.errors?
  end

  def outcome(audit)
    if passed?(audit)
      "passed"
    else
      "errored with #{audit.errors.map { |e| e.fetch(:message).inspect }.join(",")}"
    end
  end

  matcher :pass do
    match do |audit|
      passed?(audit)
    end

    failure_message do |audit|
      "expected to pass, but #{outcome(audit)}"
    end
  end

  matcher :error_with do |message|
    match do |audit|
      include_msg?(audit.errors, message)
    end

    failure_message do |audit|
      "expected to error with message #{message.inspect} but #{outcome(audit)}"
    end
  end

  let(:cask) { instance_double(Cask::Cask) }
  let(:new_cask) { nil }
  let(:online) { nil }
  let(:only) { [] }
  let(:except) { [] }
  let(:strict) { nil }
  let(:token_conflicts) { nil }
  let(:signing) { nil }
  let(:audit) do
    described_class.new(cask, online:,
                              strict:,
                              new_cask:,
                              token_conflicts:,
                              signing:,
                              only:,
                              except:)
  end

  describe "#new" do
    context "when `new_cask` is specified" do
      let(:new_cask) { true }

      it "implies `online`" do
        expect(audit).to be_online
      end

      it "implies `strict`" do
        expect(audit).to be_strict
      end

      it "implies `token_conflicts`" do
        expect(audit.token_conflicts?).to be true
      end
    end

    context "when `online` is specified" do
      let(:online) { true }

      it "implies `download`" do
        expect(audit.download).to be_truthy
      end
    end

    context "when `signing` is specified" do
      let(:signing) { true }

      it "implies `download`" do
        expect(audit.download).to be_truthy
      end
    end
  end

  describe "#result" do
    subject { audit.result }

    context "when there are no errors and `--strict` is not passed so we should not show anything" do
      before do
        audit.add_error("eh", strict_only: true)
      end

      it { is_expected.not_to match(/failed/) }
    end

    context "when there are errors" do
      before do
        audit.add_error "bad"
      end

      it { is_expected.to match(/failed/) }
    end

    context "when there are errors and warnings" do
      before do
        audit.add_error "bad"
        audit.add_error("eh", strict_only: true)
      end

      it { is_expected.to match(/failed/) }
    end

    context "when there are errors and warnings and `--strict` is passed" do
      let(:strict) { true }

      before do
        audit.add_error "very bad"
        audit.add_error("a little bit bad", strict_only: true)
      end

      it { is_expected.to match(/failed/) }
    end

    context "when there are warnings and `--strict` is not passed" do
      before do
        audit.add_error("a little bit bad", strict_only: true)
      end

      it { is_expected.not_to match(/failed/) }
    end

    context "when there are warnings and `--strict` is passed" do
      let(:strict) { true }

      before do
        audit.add_error("a little bit bad", strict_only: true)
      end

      it { is_expected.to match(/failed/) }
    end
  end

  describe "#run!" do
    subject(:run) { audit.run! }

    def tmp_cask(name, text)
      path = Pathname.new "#{dir}/#{name}.rb"
      path.open("w") do |f|
        f.write text
      end

      Cask::CaskLoader.load(path)
    end

    let(:dir) { mktmpdir }
    let(:cask) { Cask::CaskLoader.load(cask_token) }

    describe "required stanzas" do
      let(:only) { ["required_stanzas"] }

      %w[version sha256 url name homepage].each do |stanza|
        context "when missing #{stanza}" do
          let(:cask_token) { "missing-#{stanza}" }

          it { is_expected.to error_with(/#{stanza} stanza is required/) }
        end
      end
    end

    describe "token validation" do
      let(:strict) { true }
      let(:only) { ["token"] }
      let(:cask) do
        tmp_cask cask_token.to_s, <<~RUBY
          cask '#{cask_token}' do
            version '1.0'
            sha256 '8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a'
            url "https://brew.sh/"
            name 'Audit'
            homepage 'https://brew.sh/'
            app 'Audit.app'
          end
        RUBY
      end

      context "when cask token is not lowercase" do
        let(:cask_token) { "Upper-Case" }

        it "fails" do
          expect(run).to error_with(/not contain uppercase/)
        end
      end

      context "when cask token is not ascii" do
        let(:cask_token) { "ascii⌘" }

        it "fails" do
          expect(run).to error_with(/not contain non-ASCII characters/)
        end
      end

      context "when cask token is @-versioned with number" do
        let(:cask_token) { "app@10" }

        it "does not fail" do
          expect(run).to pass
        end
      end

      context "when cask token is @-versioned with word" do
        let(:cask_token) { "app@beta" }

        it "does not fail" do
          expect(run).to pass
        end
      end

      context "when cask token has multiple @" do
        let(:cask_token) { "app@stuff@beta" }

        it "fails" do
          expect(run).to error_with(/not contain multiple @ symbols/)
        end
      end

      context "when cask token has a hyphen followed by @" do
        let(:cask_token) { "app-@beta" }

        it "fails" do
          expect(run).to error_with(/not contain a hyphen followed by an @/)
        end
      end

      context "when cask token has @ followed by a hyphen" do
        let(:cask_token) { "app@-beta" }

        it "fails" do
          expect(run).to error_with(/not contain an @ followed by a hyphen/)
        end
      end

      context "when cask token has whitespace" do
        let(:cask_token) { "app stuff" }

        it "fails" do
          expect(run).to error_with(/not contain whitespace/)
        end
      end

      context "when cask token has double hyphens" do
        let(:cask_token) { "app--stuff" }

        it "fails" do
          expect(run).to error_with(/not contain double hyphens/)
        end
      end

      context "when cask token has leading hyphens" do
        let(:cask_token) { "-app" }

        it "fails" do
          expect(run).to error_with(/not contain a leading hyphen/)
        end
      end

      context "when cask token has trailing hyphens" do
        let(:cask_token) { "app-" }

        it "fails" do
          expect(run).to error_with(/not contain a trailing hyphen/)
        end
      end
    end

    describe "token bad words" do
      let(:new_cask) { true }
      let(:only) { ["token_bad_words", "reverse_migration"] }
      let(:online) { false }
      let(:cask) do
        tmp_cask cask_token.to_s, <<~RUBY
          cask "#{cask_token}" do
            version "1.0"
            sha256 "8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a"
            url "https://brew.sh/v\#{version}.zip"
            name "Audit"
            desc "Cask for testing tokens"
            homepage "https://brew.sh/"
            app "Audit.app"
          end
        RUBY
      end

      context "when cask token contains .app" do
        let(:cask_token) { "token.app" }

        it "fails" do
          expect(run).to error_with(/token contains .app/)
        end
      end

      context "when cask token contains launcher" do
        let(:cask_token) { "token-launcher" }

        it "fails" do
          expect(run).to error_with(/token mentions launcher/)
        end
      end

      context "when cask token contains desktop" do
        let(:cask_token) { "token-desktop" }

        it "fails" do
          expect(run).to error_with(/token mentions desktop/)
        end
      end

      context "when cask token contains platform" do
        let(:cask_token) { "token-osx" }

        it "fails" do
          expect(run).to error_with(/token mentions platform/)
        end
      end

      context "when cask token contains architecture" do
        let(:cask_token) { "token-x86" }

        it "fails" do
          expect(run).to error_with(/token mentions architecture/)
        end
      end

      context "when cask token contains framework" do
        let(:cask_token) { "token-java" }

        it "fails" do
          expect(run).to error_with(/cask token mentions framework/)
        end
      end

      context "when cask token is framework" do
        let(:cask_token) { "java" }

        it "does not fail" do
          expect(run).to pass
        end
      end

      context "when cask token is in tap_migrations.json and" do
        let(:cask_token) { "token-migrated" }
        let(:tap) { CoreCaskTap.instance }

        before do
          allow(tap).to receive(:tap_migrations).and_return({ cask_token => "homebrew/core" })
          allow(cask).to receive(:tap).and_return(tap)
        end

        context "when `new_cask` is true" do
          let(:new_cask) { true }

          it "fails" do
            expect(run).to error_with("#{cask_token} is listed in tap_migrations.json")
          end
        end

        context "when `new_cask` is false" do
          let(:new_cask) { false }

          it "does not fail" do
            expect(run).to pass
          end
        end
      end
    end

    describe "locale validation" do
      let(:only) { ["languages"] }
      let(:cask) do
        tmp_cask "locale-cask-test", <<~RUBY
          cask 'locale-cask-test' do
            version '1.0'
            url "https://brew.sh/"
            name 'Audit'
            homepage 'https://brew.sh/'
            app 'Audit.app'

            language 'en', default: true do
              sha256 '96574251b885c12b48a3495e843e434f9174e02bb83121b578e17d9dbebf1ffb'
              'zh-CN'
            end

            language 'zh-CN' do
              sha256 '96574251b885c12b48a3495e843e434f9174e02bb83121b578e17d9dbebf1ffb'
              'zh-CN'
            end

            language 'ZH-CN' do
              sha256 '96574251b885c12b48a3495e843e434f9174e02bb83121b578e17d9dbebf1ffb'
              'zh-CN'
            end

            language 'zh-' do
              sha256 '96574251b885c12b48a3495e843e434f9174e02bb83121b578e17d9dbebf1ffb'
              'zh-CN'
            end

            language 'zh-cn' do
              sha256 '96574251b885c12b48a3495e843e434f9174e02bb83121b578e17d9dbebf1ffb'
              'zh-CN'
            end
          end
        RUBY
      end

      context "when cask locale is invalid" do
        it "error with invalid locale" do
          expect(run).to error_with(/Locale 'ZH-CN' is invalid\./)
          expect(run).to error_with(/Locale 'zh-' is invalid\./)
          expect(run).to error_with(/Locale 'zh-cn' is invalid\./)
        end
      end
    end

    describe "pkg allow_untrusted checks" do
      let(:only) { ["untrusted_pkg"] }
      let(:message) { "allow_untrusted is not permitted in official Homebrew Cask taps" }

      context "when the Cask has no pkg stanza" do
        let(:cask_token) { "basic-cask" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask does not have allow_untrusted" do
        let(:cask_token) { "with-uninstall-pkgutil" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has allow_untrusted" do
        let(:cask_token) { "with-allow-untrusted" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "signing checks" do
      let(:only) { ["signing"] }
      let(:download_double) { instance_double(Cask::Download) }
      let(:unpack_double) { instance_double(UnpackStrategy::Zip) }

      before do
        allow(audit).to receive_messages(download: download_double, signing?: true)
      end

      context "when cask is not using a signed artifact" do
        let(:cask) do
          tmp_cask "signing-cask-test", <<~RUBY
            cask 'signing-cask-test' do
              version '1.0'
              url "https://brew.sh/index.html"
              artifact "example.pdf", target: "/Library/Application Support/example"
            end
          RUBY
        end

        it "does not fail" do
          expect(download_double).not_to receive(:fetch)
          expect(UnpackStrategy).not_to receive(:detect)
          expect(run).not_to error_with(/Audit\.app/)
        end
      end

      context "when cask is using a signed artifact" do
        let(:cask) do
          tmp_cask "signing-cask-test", <<~RUBY
            cask 'signing-cask-test' do
              version '1.0'
              url "https://brew.sh/"
              pkg 'Audit.app'
            end
          RUBY
        end

        it "does not fail since no extract" do
          allow(download_double).to receive(:fetch).and_return(Pathname.new("/tmp/test.zip"))
          allow(UnpackStrategy).to receive(:detect).and_return(nil)
          expect(run).not_to error_with(/Audit\.app/)
        end
      end
    end

    describe "livecheck should be skipped" do
      let(:only) { ["livecheck_version"] }
      let(:online) { true }
      let(:message) { /Version '[^']*' differs from '[^']*' retrieved by livecheck\./ }

      context "when the Cask has a `livecheck` block using skip" do
        let(:cask_token) { "livecheck-skip" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has a `livecheck` block referencing a Cask using skip" do
        let(:cask_token) { "livecheck-skip-reference" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask is deprecated" do
        let(:cask_token) { "livecheck-deprecated" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has a `livecheck` block referencing a deprecated Cask" do
        let(:cask_token) { "livecheck-deprecated-reference" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask is disabled" do
        let(:cask_token) { "livecheck-disabled" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has a `livecheck` block referencing a disabled Cask" do
        let(:cask_token) { "livecheck-disabled-reference" }

        it { is_expected.not_to error_with(message) }
      end

      context "when version is :latest" do
        let(:cask_token) { "livecheck-version-latest" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has a `livecheck` block referencing a Cask where version is :latest" do
        let(:cask_token) { "livecheck-version-latest-reference" }

        it { is_expected.not_to error_with(message) }
      end

      context "when url is unversioned" do
        let(:cask_token) { "livecheck-url-unversioned" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has a `livecheck` block referencing a Cask with an unversioned url" do
        let(:cask_token) { "livecheck-url-unversioned-reference" }

        it { is_expected.not_to error_with(message) }
      end
    end

    describe "when the Cask stanza requires uninstall" do
      let(:only) { ["stanza_requires_uninstall"] }
      let(:message) { "installer and pkg stanzas require an uninstall stanza" }

      context "when the Cask does not require an uninstall" do
        let(:cask_token) { "basic-cask" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the pkg Cask has an uninstall" do
        let(:cask_token) { "with-uninstall-pkgutil" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the installer Cask has an uninstall" do
        let(:cask_token) { "installer-with-uninstall" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the installer Cask does not have an uninstall" do
        let(:cask_token) { "with-installer-manual" }

        it { is_expected.to error_with(message) }
      end

      context "when the pkg Cask does not have an uninstall" do
        let(:cask_token) { "pkg-without-uninstall" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "preflight stanza checks" do
      let(:message) { "only a single preflight stanza is allowed" }

      context "when the Cask has no preflight stanza" do
        let(:cask_token) { "with-zap-rmdir" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has only one preflight stanza" do
        let(:cask_token) { "with-preflight" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has multiple preflight stanzas" do
        let(:cask_token) { "with-preflight-multi" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "postflight stanza checks" do
      let(:message) { "only a single postflight stanza is allowed" }

      context "when the Cask has no postflight stanza" do
        let(:cask_token) { "with-zap-rmdir" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has only one postflight stanza" do
        let(:cask_token) { "with-postflight" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has multiple postflight stanzas" do
        let(:cask_token) { "with-postflight-multi" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "uninstall_preflight stanza checks" do
      let(:message) { "only a single uninstall_preflight stanza is allowed" }

      context "when the Cask has no uninstall_preflight stanza" do
        let(:cask_token) { "with-zap-rmdir" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has only one uninstall_preflight stanza" do
        let(:cask_token) { "with-uninstall-preflight" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has multiple uninstall_preflight stanzas" do
        let(:cask_token) { "with-uninstall-preflight-multi" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "uninstall_postflight stanza checks" do
      let(:message) { "only a single uninstall_postflight stanza is allowed" }

      context "when the Cask has no uninstall_postflight stanza" do
        let(:cask_token) { "with-zap-rmdir" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has only one uninstall_postflight stanza" do
        let(:cask_token) { "with-uninstall-postflight" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has multiple uninstall_postflight stanzas" do
        let(:cask_token) { "with-uninstall-postflight-multi" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "zap stanza checks" do
      let(:message) { "only a single zap stanza is allowed" }

      context "when the Cask has no zap stanza" do
        let(:cask_token) { "with-uninstall-rmdir" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has only one zap stanza" do
        let(:cask_token) { "with-zap-rmdir" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask has multiple zap stanzas" do
        let(:cask_token) { "with-zap-multi" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "version checks" do
      let(:message) { "you should use version :latest instead of version 'latest'" }

      context "when version is 'latest'" do
        let(:only) { ["no_string_version_latest"] }
        let(:cask_token) { "version-latest-string" }

        it { is_expected.to error_with(message) }
      end

      context "when version is :latest" do
        let(:only) { ["sha256_no_check_if_latest"] }
        let(:cask_token) { "version-latest-with-checksum" }

        it { is_expected.not_to error_with(message) }
      end

      context "when version contains a colon" do
        let(:only) { ["version_special_characters"] }
        let(:cask_token) { "version-colon" }
        let(:message) { "version should not contain colons or slashes" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "sha256 checks" do
      context "when version is :latest and sha256 is not :no_check" do
        let(:only) { ["sha256_no_check_if_latest"] }
        let(:cask_token) { "version-latest-with-checksum" }

        it { is_expected.to error_with("you should use sha256 :no_check when version is :latest") }
      end

      context "when sha256 is not a legal SHA-256 digest" do
        let(:only) { ["sha256_actually_256"] }
        let(:cask_token) { "invalid-sha256" }

        it { is_expected.to error_with("sha256 string must be of 64 hexadecimal characters") }
      end

      context "when sha256 is sha256 for empty string" do
        let(:only) { ["sha256_invalid"] }
        let(:cask_token) { "sha256-for-empty-string" }

        it { is_expected.to error_with(/cannot use the sha256 for an empty string/) }
      end
    end

    describe "hosting with livecheck checks" do
      let(:only) { ["hosting_with_livecheck"] }
      let(:message) { /please add a livecheck/ }

      context "when the download does not use hosting with a livecheck" do
        let(:cask_token) { "basic-cask" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the download is hosted on SourceForge and has a livecheck" do
        let(:cask_token) { "sourceforge-with-livecheck" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the download is hosted on SourceForge and does not have a livecheck" do
        let(:cask_token) { "sourceforge-correct-url-format" }
        let(:online) { true }

        it { is_expected.to error_with(message) }
      end

      context "when the download is hosted on DevMate and has a livecheck" do
        let(:cask_token) { "devmate-with-livecheck" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the download is hosted on DevMate and does not have a livecheck" do
        let(:cask_token) { "devmate-without-livecheck" }

        it { is_expected.to error_with(message) }
      end

      context "when the download is hosted on HockeyApp and has a livecheck" do
        let(:cask_token) { "hockeyapp-with-livecheck" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the download is hosted on HockeyApp and does not have a livecheck" do
        let(:cask_token) { "hockeyapp-without-livecheck" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "latest with livecheck checks" do
      let(:only) { ["latest_with_livecheck"] }
      let(:message) { "Casks with a `livecheck` should not use `version :latest`." }

      context "when the Cask is :latest and does not have a livecheck" do
        let(:cask_token) { "version-latest" }

        it { is_expected.not_to error_with(message) }
      end

      context "when the Cask is versioned and has a livecheck with skip information" do
        let(:cask_token) { "latest-with-livecheck-skip" }

        it { is_expected.to pass }
      end

      context "when the Cask is versioned and has a livecheck" do
        let(:cask_token) { "latest-with-livecheck" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "denylist checks" do
      let(:only) { ["denylist"] }

      context "when the Cask is not on the denylist" do
        let(:cask_token) { "adobe-air" }

        it { is_expected.to pass }
      end

      context "when the Cask is on the denylist and" do
        context "when it's in the official Homebrew tap" do
          let(:cask_token) { "adobe-illustrator" }

          it { is_expected.to error_with(/#{cask_token} is not allowed: \w+/) }
        end

        context "when it isn't in the official Homebrew tap" do
          let(:cask_token) { "pharo" }

          it { is_expected.to pass }
        end
      end
    end

    describe "latest with auto_updates checks" do
      let(:only) { ["latest_with_auto_updates"] }
      let(:message) { "Casks with `version :latest` should not use `auto_updates`." }

      context "when the Cask is :latest and does not have auto_updates" do
        let(:cask_token) { "version-latest" }

        it { is_expected.to pass }
      end

      context "when the Cask is versioned and does not have auto_updates" do
        let(:cask_token) { "basic-cask" }

        it { is_expected.to pass }
      end

      context "when the Cask is versioned and has auto_updates" do
        let(:cask_token) { "auto-updates" }

        it { is_expected.to pass }
      end

      context "when the Cask is :latest and has auto_updates" do
        let(:cask_token) { "latest-with-auto-updates" }

        it { is_expected.to error_with(message) }
      end
    end

    describe "preferred download URL formats" do
      let(:only) { ["download_url_format"] }
      let(:message) { /URL format incorrect/ }

      context "with incorrect SourceForge URL format" do
        let(:cask_token) { "sourceforge-incorrect-url-format" }

        it { is_expected.to error_with(message) }
      end

      context "with correct SourceForge URL format" do
        let(:cask_token) { "sourceforge-correct-url-format" }

        it { is_expected.not_to error_with(message) }
      end

      context "with correct SourceForge URL format for version :latest" do
        let(:cask_token) { "sourceforge-version-latest-correct-url-format" }

        it { is_expected.not_to error_with(message) }
      end
    end

    describe "disable OSDN download url" do
      let(:only) { ["download_url_is_osdn"] }
      let(:message) { /OSDN download urls are disabled./ }
      let(:cask_token) { "osdn-urls" }

      context "when --strict is not passed" do
        it { is_expected.not_to error_with(message) }
      end

      context "when --strict is passed" do
        let(:strict) { true }

        it { is_expected.to error_with(message) }
      end
    end

    describe "generic artifact checks" do
      let(:only) { ["generic_artifacts"] }

      context "with relative target" do
        let(:cask_token) { "generic-artifact-relative-target" }

        it { is_expected.to error_with(/target must be.*absolute/) }
      end

      context "with user-relative target" do
        let(:cask_token) { "generic-artifact-user-relative-target" }

        it { is_expected.not_to error_with(/target must be.*absolute/) }
      end

      context "with absolute target" do
        let(:cask_token) { "generic-artifact-absolute-target" }

        it { is_expected.not_to error_with(/target must be.*absolute/) }
      end
    end

    describe "token conflicts" do
      let(:only) { ["token_conflicts"] }
      let(:cask_token) { "with-binary" }
      let(:token_conflicts) { true }

      context "when cask token conflicts with a core formula" do
        let(:formula_names) { %w[with-binary other-formula] }

        context "when `--strict` is passed" do
          let(:strict) { true }

          it "warns about duplicates" do
            expect(audit).to receive(:core_formula_names).and_return(formula_names)
            expect(run).to error_with(/possible duplicate/)
          end
        end

        context "when `--strict` is not passed" do
          it "does not warn about duplicates" do
            expect(audit).to receive(:core_formula_names).and_return(formula_names)
            expect(run).not_to error_with(/possible duplicate/)
          end
        end
      end

      context "when cask token does not conflict with a core formula" do
        let(:formula_names) { %w[other-formula] }

        it { is_expected.to pass }
      end
    end

    describe "audit of downloads" do
      let(:only) { ["download"] }
      let(:cask_token) { "basic-cask" }
      let(:cask) { Cask::CaskLoader.load(cask_token) }
      let(:download_double) { instance_double(Cask::Download) }
      let(:message) { "Download Failed" }

      before do
        allow(audit).to receive(:download).and_return(download_double)
        allow(UnpackStrategy).to receive(:detect).and_return(nil)
      end

      it "when download and verification succeed it does not fail" do
        expect(download_double).to receive(:fetch).and_return(Pathname.new("/tmp/test.zip"))
        expect(run).to pass
      end

      it "when download fails it fails" do
        expect(download_double).to receive(:fetch).and_raise(StandardError.new(message))
        expect(run).to error_with(/#{message}/)
      end
    end

    context "when an exception is raised" do
      let(:cask) { instance_double(Cask::Cask) }
      let(:only) { ["description"] }

      it "fails the audit" do
        expect(cask).to receive(:tap).and_raise(StandardError.new)
        expect(run).to error_with(/exception while auditing/)
      end
    end

    describe "checking description" do
      let(:only) { ["description"] }
      let(:cask_token) { "without-description" }
      let(:cask) do
        tmp_cask cask_token.to_s, <<~RUBY
          cask '#{cask_token}' do
            version '1.0'
            sha256 '8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a'
            url "https://brew.sh/"
            name 'Audit'
            homepage 'https://brew.sh/'
            app 'Audit.app'
          end
        RUBY
      end

      context "when `new_cask` is true" do
        let(:new_cask) { true }

        it "fails" do
          expect(run).to error_with(/should have a description/)
        end
      end

      context "when `new_cask` is false" do
        let(:new_cask) { false }

        it "does not warn" do
          expect(run).not_to error_with(/should have a description/)
        end
      end

      context "with description" do
        let(:cask_token) { "with-description" }
        let(:cask) do
          tmp_cask cask_token.to_s, <<~RUBY
            cask "#{cask_token}" do
              version "1.0"
              sha256 "8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a"
              url "https://brew.sh/\#{version}.zip"
              name "Audit"
              desc "Cask Auditor"
              homepage "https://brew.sh/"
              app "Audit.app"
            end
          RUBY
        end

        it "passes" do
          expect(run).to pass
        end
      end
    end

    describe "checking verified" do
      let(:only) { %w[unnecessary_verified missing_verified no_match required_stanzas] }
      let(:cask_token) { "foo" }

      context "when the url matches the homepage" do
        let(:cask) do
          tmp_cask cask_token.to_s, <<~RUBY
            cask '#{cask_token}' do
              version '1.0'
              sha256 '8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a'
              url 'https://foo.brew.sh/foo.zip'
              name 'Audit'
              desc 'Audit Description'
              homepage 'https://foo.brew.sh'
              app 'Audit.app'
            end
          RUBY
        end

        it { is_expected.to pass }
      end

      context "when the url does not match the homepage" do
        let(:cask) do
          tmp_cask cask_token.to_s, <<~RUBY
            cask '#{cask_token}' do
              version "1.8.0_72,8.13.0.5"
              sha256 "8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a"
              url "https://brew.sh/foo-\#{version.after_comma}.zip"
              name "Audit"
              desc "Audit Description"
              homepage "https://foo.example.org"
              app "Audit.app"
            end
          RUBY
        end

        it { is_expected.to error_with(/a 'verified' parameter has to be added/) }
      end

      context "when the url does not match the homepage with verified" do
        let(:cask) do
          tmp_cask cask_token.to_s, <<~RUBY
            cask "#{cask_token}" do
              version "1.8.0_72,8.13.0.5"
              sha256 "8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a"
              url "https://brew.sh/foo-\#{version.after_comma}.zip", verified: "brew.sh"
              name "Audit"
              desc "Audit Description"
              homepage "https://foo.example.org"
              app "Audit.app"
            end
          RUBY
        end

        it { is_expected.to pass }
      end

      context "when there is no homepage" do
        let(:cask) do
          tmp_cask cask_token.to_s, <<~RUBY
            cask '#{cask_token}' do
              version '1.8.0_72,8.13.0.5'
              sha256 '8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a'
              url 'https://brew.sh/foo.zip'
              name 'Audit'
              desc 'Audit Description'
              app 'Audit.app'
            end
          RUBY
        end

        it { is_expected.to error_with(/a homepage stanza is required/) }
      end
    end

    describe "checking deprecate/disable" do
      let(:only) { ["deprecate_disable"] }
      let(:cask_token) { "deprecated-cask" }

      context "when deprecate/disable is used with a valid reason" do
        let(:cask) do
          tmp_cask cask_token.to_s, <<~RUBY
            cask '#{cask_token}' do
              version "1.0"
                sha256 "8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a"
                url "https://brew.sh/foo.zip"
                name "Audit"
                desc "Cask Auditor"
                homepage "https://brew.sh/"
                app "Audit.app"
                deprecate! date: "2021-01-01", because: :foobar
            end
          RUBY
        end

        it "fails" do
          expect(run).to error_with(/foobar is not a valid deprecate! or disable! reason/)
        end
      end

      context "when deprecate/disable is used with an invalid reason" do
        let(:cask) do
          tmp_cask cask_token.to_s, <<~RUBY
            cask '#{cask_token}' do
              version "1.0"
                sha256 "8dd95daa037ac02455435446ec7bc737b34567afe9156af7d20b2a83805c1d8a"
                url "https://brew.sh/foo.zip"
                name "Audit"
                desc "Cask Auditor"
                homepage "https://brew.sh/"
                app "Audit.app"
                disable! date: "2021-01-01", because: :discontinued
            end
          RUBY
        end

        it "passes" do
          expect(run).to pass
        end
      end
    end
  end
end
