# frozen_string_literal: true

RSpec.describe Cask::DSL, :cask, :no_api do
  let(:cask) { Cask::CaskLoader.load(token) }
  let(:token) { "basic-cask" }

  describe "stanzas" do
    it "lets you set url, homepage and version" do
      expect(cask.url.to_s).to eq("https://brew.sh/TestCask-1.2.3.dmg")
      expect(cask.homepage).to eq("https://brew.sh/")
      expect(cask.version.to_s).to eq("1.2.3")
    end
  end

  describe "when a Cask includes an unknown method" do
    let(:attempt_unknown_method) do
      Cask::Cask.new("unexpected-method-cask") do
        future_feature :not_yet_on_your_machine
      end
    end

    it "prints an error that it has encountered an unexpected method" do
      expected = Regexp.compile(<<~EOS.lines.map(&:chomp).join)
        (?m)
        Error: Unexpected method 'future_feature' called on Cask unexpected-method-cask\\.
        .*
        https://github.com/Homebrew/homebrew-cask#reporting-bugs
      EOS

      expect do
        expect { attempt_unknown_method }.not_to output.to_stdout
      end.to output(expected).to_stderr
    end

    it "simply warns, instead of throwing an exception" do
      expect do
        attempt_unknown_method
      end.not_to raise_error
    end
  end

  describe "header line" do
    context "when invalid" do
      let(:token) { "invalid-header-format" }

      it "raises an error" do
        expect { cask }.to raise_error(Cask::CaskUnreadableError)
      end
    end

    context "when token does not match the file name" do
      let(:token) { "invalid-header-token-mismatch" }

      it "raises an error" do
        expect do
          cask
        end.to raise_error(Cask::CaskTokenMismatchError, /header line does not match the file name/)
      end
    end

    context "when it contains no DSL version" do
      let(:token) { "no-dsl-version" }

      it "does not require a DSL version in the header" do
        expect(cask.token).to eq("no-dsl-version")
        expect(cask.url.to_s).to eq("https://brew.sh/TestCask-1.2.3.dmg")
        expect(cask.homepage).to eq("https://brew.sh/")
        expect(cask.version.to_s).to eq("1.2.3")
      end
    end
  end

  describe "name stanza" do
    it "lets you set the full name via a name stanza" do
      cask = Cask::Cask.new("name-cask") do
        name "Proper Name"
      end

      expect(cask.name).to eq([
        "Proper Name",
      ])
    end

    it "Accepts an array value to the name stanza" do
      cask = Cask::Cask.new("array-name-cask") do
        name ["Proper Name", "Alternate Name"]
      end

      expect(cask.name).to eq([
        "Proper Name",
        "Alternate Name",
      ])
    end

    it "Accepts multiple name stanzas" do
      cask = Cask::Cask.new("multi-name-cask") do
        name "Proper Name"
        name "Alternate Name"
      end

      expect(cask.name).to eq([
        "Proper Name",
        "Alternate Name",
      ])
    end
  end

  describe "desc stanza" do
    it "lets you set the description via a desc stanza" do
      cask = Cask::Cask.new("desc-cask") do
        desc "The package's description"
      end

      expect(cask.desc).to eq("The package's description")
    end
  end

  describe "sha256 stanza" do
    it "lets you set checksum via sha256" do
      cask = Cask::Cask.new("checksum-cask") do
        sha256 "imasha2"
      end

      expect(cask.sha256).to eq("imasha2")
    end

    context "with a different arm and intel checksum" do
      let(:cask) do
        Cask::Cask.new("checksum-cask") do
          sha256 arm: "imasha2arm", intel: "imasha2intel"
        end
      end

      context "when running on arm" do
        before do
          allow(Hardware::CPU).to receive(:type).and_return(:arm)
        end

        it "stores only the arm checksum" do
          expect(cask.sha256).to eq("imasha2arm")
        end
      end

      context "when running on intel" do
        before do
          allow(Hardware::CPU).to receive(:type).and_return(:intel)
        end

        it "stores only the intel checksum" do
          expect(cask.sha256).to eq("imasha2intel")
        end
      end
    end
  end

  describe "no_autobump! stanze" do
    it "returns true if no_autobump! is not set" do
      expect(cask.autobump?).to be(true)
    end

    context "when no_autobump! is set" do
      let(:cask) do
        Cask::Cask.new("checksum-cask") do
          no_autobump! because: "some reason"
        end
      end

      it "returns false" do
        expect(cask.autobump?).to be(false)
        expect(cask.no_autobump_message).to eq("some reason")
      end
    end
  end

  describe "language stanza" do
    context "when language is set explicitly" do
      subject(:cask) do
        Cask::Cask.new("cask-with-apps") do
          language "zh" do
            sha256 "abc123"
            "zh-CN"
          end

          language "en", default: true do
            sha256 "xyz789"
            "en-US"
          end

          url "https://example.org/#{language}.zip"
        end
      end

      matcher :be_the_chinese_version do
        match do |cask|
          expect(cask.language).to eq("zh-CN")
          expect(cask.sha256).to eq("abc123")
          expect(cask.url.to_s).to eq("https://example.org/zh-CN.zip")
        end
      end

      matcher :be_the_english_version do
        match do |cask|
          expect(cask.language).to eq("en-US")
          expect(cask.sha256).to eq("xyz789")
          expect(cask.url.to_s).to eq("https://example.org/en-US.zip")
        end
      end

      before do
        config = cask.config
        config.languages = languages
        cask.config = config
      end

      describe "to 'zh'" do
        let(:languages) { ["zh"] }

        it { is_expected.to be_the_chinese_version }
      end

      describe "to 'zh-XX'" do
        let(:languages) { ["zh-XX"] }

        it { is_expected.to be_the_chinese_version }
      end

      describe "to 'en'" do
        let(:languages) { ["en"] }

        it { is_expected.to be_the_english_version }
      end

      describe "to 'xx-XX'" do
        let(:languages) { ["xx-XX"] }

        it { is_expected.to be_the_english_version }
      end

      describe "to 'xx-XX,zh,en'" do
        let(:languages) { ["xx-XX", "zh", "en"] }

        it { is_expected.to be_the_chinese_version }
      end

      describe "to 'xx-XX,en-US,zh'" do
        let(:languages) { ["xx-XX", "en-US", "zh"] }

        it { is_expected.to be_the_english_version }
      end
    end

    it "returns an empty array if no languages are specified" do
      cask = lambda do
        Cask::Cask.new("cask-with-apps") do
          url "https://example.org/file.zip"
        end
      end

      expect(cask.call.languages).to be_empty
    end

    it "returns an array of available languages" do
      cask = lambda do
        Cask::Cask.new("cask-with-apps") do
          language "zh" do
            sha256 "abc123"
            "zh-CN"
          end

          language "en-US", default: true do
            sha256 "xyz789"
            "en-US"
          end

          url "https://example.org/file.zip"
        end
      end

      expect(cask.call.languages).to eq(["zh", "en-US"])
    end
  end

  describe "app stanza" do
    it "allows you to specify app stanzas" do
      cask = Cask::Cask.new("cask-with-apps") do
        app "Foo.app"
        app "Bar.app"
      end

      expect(cask.artifacts.map(&:to_s)).to eq(["Foo.app (App)", "Bar.app (App)"])
    end

    it "allow app stanzas to be empty" do
      cask = Cask::Cask.new("cask-with-no-apps")
      expect(cask.artifacts).to be_empty
    end
  end

  describe "caveats stanza" do
    it "allows caveats to be specified via a method define" do
      cask = Cask::Cask.new("plain-cask")

      expect(cask.caveats).to be_empty

      cask = Cask::Cask.new("cask-with-caveats") do
        def caveats
          <<~EOS
            When you install this Cask, you probably want to know this.
          EOS
        end
      end

      expect(cask.caveats).to eq("When you install this Cask, you probably want to know this.\n")
    end
  end

  describe "pkg stanza" do
    it "allows installable pkgs to be specified" do
      cask = Cask::Cask.new("cask-with-pkgs") do
        pkg "Foo.pkg"
        pkg "Bar.pkg"
      end

      expect(cask.artifacts.map(&:to_s)).to eq(["Foo.pkg (Pkg)", "Bar.pkg (Pkg)"])
    end
  end

  describe "url stanza" do
    let(:token) { "invalid-two-url" }

    it "prevents defining multiple urls" do
      expect { cask }.to raise_error(Cask::CaskInvalidError, /'url' stanza may only appear once/)
    end
  end

  describe "homepage stanza" do
    let(:token) { "invalid-two-homepage" }

    it "prevents defining multiple homepages" do
      expect { cask }.to raise_error(Cask::CaskInvalidError, /'homepage' stanza may only appear once/)
    end
  end

  describe "version stanza" do
    let(:token) { "invalid-two-version" }

    it "prevents defining multiple versions" do
      expect { cask }.to raise_error(Cask::CaskInvalidError, /'version' stanza may only appear once/)
    end
  end

  describe "arch stanza" do
    let(:token) { "invalid-two-arch" }

    it "prevents defining multiple arches" do
      expect { cask }.to raise_error(Cask::CaskInvalidError, /'arch' stanza may only appear once/)
    end

    context "when no intel value is specified" do
      let(:token) { "arch-arm-only" }

      context "when running on arm" do
        before do
          allow(Hardware::CPU).to receive(:type).and_return(:arm)
        end

        it "returns the value" do
          expect(cask.url.to_s).to eq "file://#{TEST_FIXTURE_DIR}/cask/caffeine-arm.zip"
        end
      end

      context "when running on intel" do
        before do
          allow(Hardware::CPU).to receive(:type).and_return(:intel)
        end

        it "defaults to `nil` for the other when no arrays are passed" do
          expect(cask.url.to_s).to eq "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
        end
      end
    end
  end

  describe "depends_on stanza" do
    let(:token) { "invalid-depends-on-key" }

    it "refuses to load with an invalid depends_on key" do
      expect { cask }.to raise_error(Cask::CaskInvalidError)
    end
  end

  describe "depends_on formula" do
    context "with one Formula" do
      let(:token) { "with-depends-on-formula" }

      it "allows depends_on formula to be specified" do
        expect(cask.depends_on.formula).not_to be_nil
      end
    end

    context "with multiple Formulae" do
      let(:token) { "with-depends-on-formula-multiple" }

      it "allows multiple depends_on formula to be specified" do
        expect(cask.depends_on.formula).not_to be_nil
      end
    end
  end

  describe "depends_on cask" do
    context "with a single cask" do
      let(:token) { "with-depends-on-cask" }

      it "is allowed" do
        expect(cask.depends_on.cask).not_to be_nil
      end
    end

    context "when specifying multiple" do
      let(:token) { "with-depends-on-cask-multiple" }

      it "is allowed" do
        expect(cask.depends_on.cask).not_to be_nil
      end
    end
  end

  describe "depends_on macos" do
    context "when the depends_on macos value is invalid" do
      let(:token) { "invalid-depends-on-macos-bad-release" }

      it "refuses to load" do
        expect { cask }.to raise_error(Cask::CaskInvalidError)
      end
    end

    context "when there are conflicting depends_on macos forms" do
      let(:token) { "invalid-depends-on-macos-conflicting-forms" }

      it "refuses to load" do
        expect { cask }.to raise_error(Cask::CaskInvalidError)
      end
    end
  end

  describe "depends_on arch" do
    context "when valid" do
      let(:token) { "with-depends-on-arch" }

      it "is allowed to be specified" do
        expect(cask.depends_on.arch).not_to be_nil
      end
    end

    context "with invalid depends_on arch value" do
      let(:token) { "invalid-depends-on-arch-value" }

      it "refuses to load" do
        expect { cask }.to raise_error(Cask::CaskInvalidError)
      end
    end
  end

  describe "conflicts_with cask" do
    let(:local_caffeine) do
      Cask::CaskLoader.load(cask_path("local-caffeine"))
    end

    let(:with_conflicts_with) do
      Cask::CaskLoader.load(cask_path("with-conflicts-with"))
    end

    it "installs the dependency of a Cask and the Cask itself" do
      Cask::Installer.new(local_caffeine).install

      expect(local_caffeine).to be_installed

      expect do
        Cask::Installer.new(with_conflicts_with).install
      end.to raise_error(Cask::CaskConflictError, "Cask 'with-conflicts-with' conflicts with 'local-caffeine'.")

      expect(with_conflicts_with).not_to be_installed
    end
  end

  describe "conflicts_with stanza" do
    context "when valid" do
      let(:token) { "with-conflicts-with" }

      it "allows conflicts_with stanza to be specified" do
        expect(cask.conflicts_with[:formula]).to be_empty
      end
    end

    context "with invalid conflicts_with key" do
      let(:token) { "invalid-conflicts-with-key" }

      it "refuses to load invalid conflicts_with key" do
        expect { cask }.to raise_error(Cask::CaskInvalidError)
      end
    end

    context "with disabled conflicts_with key" do
      let(:token) { "conflicts-with-disabled-key" }

      it "loads but shows disabled warning for disabled key" do
        expect { cask.conflicts_with }.to raise_error(Cask::CaskInvalidError, /is disabled/)
      end
    end
  end

  describe "installer stanza" do
    context "when script" do
      let(:token) { "with-installer-script" }

      it "allows installer script to be specified" do
        expect(cask.artifacts.to_a.first.path).to eq(Pathname("/usr/bin/true"))
        expect(cask.artifacts.to_a.first.args[:args]).to eq(["--flag"])
        expect(cask.artifacts.to_a.second.path).to eq(Pathname("/usr/bin/false"))
        expect(cask.artifacts.to_a.second.args[:args]).to eq(["--flag"])
      end
    end

    context "when manual" do
      let(:token) { "with-installer-manual" }

      it "allows installer manual to be specified" do
        installer = cask.artifacts.first
        expect(installer.instance_variable_get(:@manual_install)).to be true
        expect(installer.path).to eq(Pathname("Caffeine.app"))
      end
    end
  end

  describe "stage_only stanza" do
    context "when there is no other activatable artifact" do
      let(:token) { "stage-only" }

      it "allows stage_only stanza to be specified" do
        expect(cask.artifacts).to contain_exactly a_kind_of Cask::Artifact::StageOnly
      end
    end

    context "when there is are activatable artifacts" do
      let(:token) { "invalid-stage-only-conflict" }

      it "prevents specifying stage_only" do
        expect { cask }.to raise_error(Cask::CaskInvalidError, /'stage_only' must be the only activatable artifact/)
      end
    end
  end

  describe "auto_updates stanza" do
    let(:token) { "auto-updates" }

    it "allows auto_updates stanza to be specified" do
      expect(cask.auto_updates).to be true
    end
  end

  describe "#appdir" do
    context "with interpolation of the appdir in stanzas" do
      let(:token) { "appdir-interpolation" }

      it "is allowed" do
        expect(cask.artifacts.first.source).to eq(cask.config.appdir/"some/path")
      end
    end

    it "does not include a trailing slash" do
      config = Cask::Config.new(explicit: {
        appdir: "/Applications/",
      })

      cask = Cask::Cask.new("appdir-trailing-slash", config:) do
        binary "#{appdir}/some/path"
      end

      expect(cask.artifacts.first.source).to eq(Pathname("/Applications/some/path"))
    end
  end

  describe "#artifacts" do
    it "sorts artifacts according to the preferable installation order" do
      cask = Cask::Cask.new("appdir-trailing-slash") do
        postflight do
          next
        end

        preflight do
          next
        end

        binary "binary"

        app "App.app"
      end

      expect(cask.artifacts.map { |artifact| artifact.class.dsl_key }).to eq [
        :preflight,
        :app,
        :binary,
        :postflight,
      ]
    end
  end

  describe "rename stanza" do
    it "allows setting single rename operation" do
      cask = Cask::Cask.new("rename-cask") do
        rename "Source*.pkg", "Target.pkg"
      end

      expect(cask.rename.length).to eq(1)
      expect(cask.rename.first.from).to eq("Source*.pkg")
      expect(cask.rename.first.to).to eq("Target.pkg")
    end

    it "allows setting multiple rename operations" do
      cask = Cask::Cask.new("multi-rename-cask") do
        rename "App*.pkg", "App.pkg"
        rename "Doc*.dmg", "Doc.dmg"
      end

      expect(cask.rename.length).to eq(2)
      expect(cask.rename.first.from).to eq("App*.pkg")
      expect(cask.rename.first.to).to eq("App.pkg")
      expect(cask.rename.last.from).to eq("Doc*.dmg")
      expect(cask.rename.last.to).to eq("Doc.dmg")
    end
  end
end
