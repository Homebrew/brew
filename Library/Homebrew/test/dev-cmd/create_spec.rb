# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/create"

RSpec.describe Homebrew::DevCmd::Create do
  let(:url) { "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz" }
  let(:formula_file) { CoreTap.instance.new_formula_path("testball") }

  it_behaves_like "parseable arguments"

  it "creates formula and cask files with the download's checksum", :integration_test do
    checksum = %Q(sha256 "#{TESTBALL_SHA256}")
    brew "create", "--set-name=Testball", url, "HOMEBREW_EDITOR" => "/bin/cat"

    expect(formula_file).to exist
    expect(formula_file.each_line.map(&:strip)).to include(checksum)

    CoreCaskTap.instance.path.mkpath
    expect(brew("create", "--cask", "--set-name=Testball", url, "HOMEBREW_EDITOR" => "/bin/cat")).to be_a_success

    expect(CoreCaskTap.instance.new_cask_path("testball").each_line.map(&:strip)).to include(checksum)
  end

  it "generates valid cask tokens" do
    t = Cask::Utils.token_from("A FooBar_Baz++!")
    expect(t).to eq("a-foobar-baz-plus-plus")
  end

  it "retains @ in cask tokens" do
    t = Cask::Utils.token_from("test@preview")
    expect(t).to eq("test@preview")
  end

  it "does not prefill a livecheck block when the app is not installed" do
    expect(described_class.new([url]).find_appcast_for(Pathname("/Applications/Nonexistent Homebrew Test.app")))
      .to be_nil
  end

  describe "#generate_zap_for" do
    subject(:generated_zap) { described_class.new([url]).generate_zap_for(app) }

    let(:app) { (mktmpdir/"Test.app").tap(&:mkpath) }
    let(:generate_zap_output) do
      "==> Scanning for files matching \"Test\"...\nzap trash: \"~/Library/Preferences/com.example.test.plist\"\n"
    end

    before do
      # Like the real `Utils.popen_read`, return the output as binary.
      allow(Utils).to receive(:popen_read)
        .with(args: [HOMEBREW_BREW_FILE, "generate-zap", "--name", app.basename(".app").to_s], err: :err)
        .and_return(generate_zap_output.b)
    end

    it { is_expected.to eq('zap trash: "~/Library/Preferences/com.example.test.plist"') }

    it "shows errors from `brew generate-zap`, e.g. a missing Full Disk Access permission" do
      expect(Utils).to receive(:popen_read)
        .with(args: [HOMEBREW_BREW_FILE, "generate-zap", "--name", "Test"], err: :err)
        .and_return(generate_zap_output.b)

      generated_zap
    end

    context "when the app is not installed" do
      let(:app) { Pathname("/Applications/Nonexistent Homebrew Test.app") }

      it { is_expected.to be_nil }
    end

    context "when `brew generate-zap` finds nothing" do
      let(:generate_zap_output) { "==> Scanning for files matching \"Test\"...\nzap :not_required\n" }

      it { is_expected.to be_nil }
    end

    context "when the app name is not ASCII" do
      let(:app) { (mktmpdir/"Übersicht.app").tap(&:mkpath) }
      let(:generate_zap_output) do
        "==> Scanning for files matching \"Übersicht\"...\nzap trash: \"~/Library/Application Support/Übersicht\"\n"
      end

      it { is_expected.to eq('zap trash: "~/Library/Application Support/Übersicht"') }
    end
  end

  describe "#find_app_in" do
    subject(:app) { create.find_app_in(download)&.first }

    let(:create) { described_class.new([url]) }
    let(:download) { TEST_FIXTURE_DIR/"cask/caffeine.zip" }

    before { allow(create).to receive(:find_appcast_for) }

    it { is_expected.to eq(Pathname("Caffeine.app")) }

    it "reads the appcast of the app in the download" do
      expect(create).to receive(:find_appcast_for)
        .with(satisfy { |path| path.basename.to_s == "Caffeine.app" && path.directory? })
      app
    end

    context "when the app is in a subdirectory" do
      let(:download) { TEST_FIXTURE_DIR/"cask/MyFancyApp.zip" }

      it { is_expected.to eq(Pathname("MyFancyApp/MyFancyApp.app")) }
    end

    context "when the download has no app" do
      let(:download) { TEST_FIXTURE_DIR/"cask/MyFancyPkg.zip" }

      it { is_expected.to be_nil }
    end

    context "when the download has several apps" do
      let(:download) { TEST_FIXTURE_DIR/"cask/caffeine-suite.zip" }

      it { is_expected.to be_nil }
    end

    context "when the download can't be unpacked" do
      before { allow(UnpackStrategy).to receive(:detect).and_raise(RuntimeError, "No mounts found") }

      it { expect { app }.to output(/Unable to unpack the download/).to_stderr }
    end
  end

  describe "#run with `--cask`" do
    subject(:cask_file) do
      create.run
      CoreCaskTap.instance.new_cask_path("test").read
    end

    let(:create) { described_class.new(["--cask", "--set-name=Test", "--no-fetch", url]) }
    let(:generated_zap) { nil }

    before do
      CoreCaskTap.instance.path.mkpath
      allow(Utils::Editor).to receive(:open)
      allow(create).to receive(:puts)
      allow(create).to receive_messages(find_appcast_for: nil, generate_zap_for: generated_zap)
    end

    it "says what to run when no `zap` stanza is generated" do
      expect(cask_file).to end_with <<~RUBY
          # Install and launch the app, then run `brew generate-zap test`.
          # Documentation: https://docs.brew.sh/Cask-Cookbook#zap-creation
          zap trash: ""
        end
      RUBY
    end

    context "when a `zap` stanza is generated" do
      let(:generated_zap) { "zap trash: [\n  \"~/Library/Caches/com.example.test\",\n]" }

      it "indents it inside the cask" do
        expect(cask_file).to end_with <<~RUBY
            # Check that each path belongs to the app.
            # Documentation: https://docs.brew.sh/Cask-Cookbook#zap-creation
            zap trash: [
              "~/Library/Caches/com.example.test",
            ]
          end
        RUBY
      end
    end

    context "when the download contains an app" do
      let(:create) do
        described_class.new(["--cask", "--set-name=Test", "--set-version=1.0",
                             "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"])
      end

      it { is_expected.to include('  app "Caffeine.app"') }

      it "scans an installed copy of that app" do
        expect(create).to receive(:generate_zap_for).with(Pathname("/Applications/Caffeine.app"))
        cask_file
      end
    end
  end
end
