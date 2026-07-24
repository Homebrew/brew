# typed: strict
# frozen_string_literal: true

require "cask/caskroom"

RSpec.describe Cask::Caskroom do
  before { described_class.expected_caskroom_group = nil }

  describe ".ensure_caskroom_exists" do
    it "changes the group when sudo is unnecessary and the group is wrong" do
      Dir.mktmpdir do |dir|
        path = Pathname(dir)/"Caskroom"
        allow(described_class).to receive(:path).and_return(path)
        allow(described_class).to receive(:caskroom_group_correct?).with(path).and_return(false)
        expect(described_class).to receive(:chgrp_path).with(path, false)

        described_class.ensure_caskroom_exists
      end
    end

    it "skips changing the group when it is already correct" do
      Dir.mktmpdir do |dir|
        path = Pathname(dir)/"Caskroom"
        allow(described_class).to receive(:path).and_return(path)
        allow(described_class).to receive(:caskroom_group_correct?).with(path).and_return(true)
        expect(described_class).not_to receive(:chgrp_path)

        described_class.ensure_caskroom_exists
      end
    end

    it "changes the group with sudo when the parent is not writable and the group is wrong" do
      Dir.mktmpdir do |dir|
        path = Pathname(dir)/"sub"/"Caskroom"
        parent = path.parent
        allow(described_class).to receive_messages(path:, caskroom_group_correct?: false)
        allow(path).to receive(:parent).and_return(parent)
        allow(parent).to receive(:writable?).and_return(false)
        allow(SystemCommand).to receive(:run)

        expect(described_class).to receive(:chgrp_path).with(path, true)

        described_class.ensure_caskroom_exists
      end
    end

    it "skips changing the group when it is already correct and the parent is not writable" do
      Dir.mktmpdir do |dir|
        path = Pathname(dir)/"sub"/"Caskroom"
        parent = path.parent
        allow(described_class).to receive_messages(path:, caskroom_group_correct?: true)
        allow(path).to receive(:parent).and_return(parent)
        allow(parent).to receive(:writable?).and_return(false)
        allow(SystemCommand).to receive(:run)

        expect(described_class).not_to receive(:chgrp_path)

        described_class.ensure_caskroom_exists
      end
    end

    it "skips sudo on Linux when the parent is user-writable", :needs_linux do
      Dir.mktmpdir do |dir|
        path = Pathname(dir)/"Caskroom"
        allow(described_class).to receive(:path).and_return(path)
        expect(SystemCommand).not_to receive(:run).with(anything, hash_including(sudo: true))
        allow(SystemCommand).to receive(:run).and_call_original

        described_class.ensure_caskroom_exists

        expect(path).to be_directory
        expect(path.stat.gid).to eq(Process.egid)
      end
    end
  end

  describe ".caskroom_group_correct?" do
    it "checks the admin group on macOS", :needs_macos do
      path = Pathname("/tmp/Caskroom")
      allow(path).to receive(:stat).and_return(instance_double(File::Stat, gid: 1))
      allow(Etc).to receive(:getgrnam).with("admin").and_return(instance_double(Etc::Group, gid: 1))

      expect(described_class.caskroom_group_correct?(path)).to be true
    end

    it "checks the current user's primary group on Linux", :needs_linux do
      group_name = "primary-group"
      path = Pathname("/tmp/Caskroom")
      allow(path).to receive(:stat).and_return(instance_double(File::Stat, gid: 1))
      allow(Etc).to receive(:getgrgid).with(Process.egid).and_return(instance_double(Etc::Group, name: group_name))
      allow(Etc).to receive(:getgrnam).with(group_name).and_return(instance_double(Etc::Group, gid: 1))

      expect(described_class.caskroom_group_correct?(path)).to be true
    end

    it "returns false when the expected group is unavailable" do
      allow(described_class).to receive(:expected_caskroom_group).and_return("missing")
      allow(Etc).to receive(:getgrnam).with("missing").and_return(nil)

      expect(described_class.caskroom_group_correct?(Pathname("/tmp/Caskroom"))).to be false
    end
  end

  describe ".cask_installed?" do
    it "checks cask metadata without loading a Cask object" do
      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:path).and_return(Pathname(dir))
        expect(described_class.cask_installed?("foo")).to be(false)

        casks_dir = Pathname(dir)/"foo/.metadata/1.0/20250101000000.000/Casks"
        casks_dir.mkpath
        (casks_dir/"foo.rb").write("cask \"foo\"\n")

        expect(described_class.cask_installed?("foo")).to be(true)
        expect(described_class.cask_installed?("homebrew/cask/foo")).to be(true)
        expect(described_class.cask_installed_version("foo")).to eq("1.0")
      end
    end

    it "checks old-token metadata" do
      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:path).and_return(Pathname(dir))
        casks_dir = Pathname(dir)/"old-foo/.metadata/1.0/20250101000000.000/Casks"
        casks_dir.mkpath
        caskfile = casks_dir/"old-foo.rb"
        caskfile.write("cask \"old-foo\"\n")

        expect(described_class.cask_installed_caskfile("foo", old_tokens: ["old-foo"])).to eq(caskfile)
      end
    end
  end

  describe ".casks" do
    sig { params(dir: Pathname, token: String, tap: T.nilable(Tap), version: String).void }
    def setup_cask_metadata(dir, token, tap: nil, version: "1.0")
      casks_dir = dir/token/".metadata"/version/"20250101000000.000"/"Casks"
      casks_dir.mkpath
      (casks_dir/"#{token}.rb").write <<~RUBY
        cask "#{token}" do
          version "#{version}"
        end
      RUBY

      receipt = dir/token/".metadata"/AbstractTab::FILENAME
      receipt.write JSON.generate({
        source: {
          tap:     tap&.name,
          version: version,
        },
      })
    end

    it "includes casks installed from untrusted taps without loading cask files" do
      token = "untrusted-cask"
      tap = Tap.fetch("thirdparty", "foo")
      cask_path = tap.cask_dir/"#{token}.rb"
      cask_path.dirname.mkpath
      cask_path.write <<~RUBY
        raise "untrusted cask evaluated"
      RUBY

      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:path).and_return(Pathname(dir))

        setup_cask_metadata(Pathname(dir), token, tap:, version: "1.0")

        with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
          casks = described_class.casks
          expect(casks.map(&:token)).to eq([token])

          cask = casks.first
          expect(cask&.installed_version).to eq("1.0")
          expect(cask&.tap).to eq(tap)
        end
      end
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "does not list a cask twice when it is also installed under an old token", :trust_store do
      tap = Tap.fetch("thirdparty", "foo")
      cask_path = tap.cask_dir/"new-cask.rb"
      cask_path.dirname.mkpath
      cask_path.write <<~RUBY
        cask "new-cask" do
          version "2.0"
        end
      RUBY
      (tap.path/"cask_renames.json").write JSON.generate("old-cask" => "new-cask")
      tap.clear_cache
      Homebrew::Trust.trust!(:tap, tap.name)

      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:path).and_return(Pathname(dir))

        setup_cask_metadata(Pathname(dir), "new-cask", tap:, version: "2.0")
        setup_cask_metadata(Pathname(dir), "old-cask", tap:, version: "1.0")

        expect(described_class.casks.map(&:token)).to eq(["new-cask"])
      end
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "does not error for ambiguous installed casks when an ambiguous tap is untrusted" do
      token = "ambiguous-untrusted-cask"
      taps = [Tap.fetch("thirdparty", "foo"), Tap.fetch("thirdparty", "bar")]
      taps.each do |tap|
        cask_path = tap.cask_dir/"#{token}.rb"
        cask_path.dirname.mkpath
        cask_path.write <<~RUBY
          cask "#{token}" do
            version "2.0"
          end
        RUBY
      end
      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:path).and_return(Pathname(dir))

        setup_cask_metadata(Pathname(dir), token, version: "1.0")

        with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") do
          casks = described_class.casks
          expect(casks.map(&:token)).to eq([token])
          expect(casks.first&.installed_version).to eq("1.0")
        end
      end
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end
  end

  describe ".migrate_caskfile_to_json" do
    sig { returns(Pathname) }
    let(:caskroom) { mktmpdir/"Caskroom" }

    before { allow(described_class).to receive(:path).and_return(caskroom) }

    sig { params(token: String, contents: String, extension: String).returns(Pathname) }
    def write_installed_caskfile(token, contents, extension: "rb")
      caskfile = caskroom/token/".metadata/1.0/20250101000000.000/Casks/#{token}.#{extension}"
      caskfile.dirname.mkpath
      caskfile.write(contents)
      caskfile
    end

    sig { params(token: String, artifacts: T::Array[T::Hash[String, T.untyped]]).void }
    def write_receipt(token, artifacts)
      (caskroom/token/".metadata/INSTALL_RECEIPT.json").write JSON.pretty_generate({
        "source"              => { "version" => "1.0" },
        "uninstall_artifacts" => artifacts,
      })
    end

    it "uses receipt metadata when a Ruby caskfile is unreadable" do
      token = "unreadable"
      caskfile = write_installed_caskfile(token, "this is not Ruby")
      write_receipt(token, [{ "app" => ["Unreadable.app"] }])

      described_class.migrate_caskfile_to_json(caskfile)

      json_caskfile = caskfile.sub_ext(".json")
      migrated_cask = Cask::CaskLoader.load_from_installed_caskfile(json_caskfile)
      expect([
        caskfile.exist?,
        JSON.parse(json_caskfile.read),
        migrated_cask.version.to_s,
        migrated_cask.artifacts_list(uninstall_only: true),
      ]).to eq([
        false,
        {},
        "1.0",
        [{ app: ["Unreadable.app"] }],
      ])
    end

    it "treats reordered receipt artifacts as equivalent" do
      token = "reordered-artifacts"
      caskfile = write_installed_caskfile(token, <<~RUBY)
        cask "#{token}" do
          version "1.0"
          font "Font0.ttf"
          font "Font1.ttf"
          font "Font2.ttf"
          font "Font3.ttf"
          font "Font4.ttf"
          font "Font5.ttf"
          font "Font6.ttf"
          font "Font7.ttf"
        end
      RUBY
      artifacts = Array.new(8) { |i| { "font" => ["Font#{i}.ttf"] } }
      write_receipt(token, artifacts)

      described_class.migrate_caskfile_to_json(caskfile)

      json_caskfile = caskfile.sub_ext(".json")
      expect([caskfile.exist?, JSON.parse(json_caskfile.read)]).to eq([false, {}])
    end

    it "restores original metadata when migrated artifact multiplicity differs" do
      token = "changed-artifacts"
      caskfile = write_installed_caskfile(token, <<~RUBY)
        cask "#{token}" do
          version "1.0"
          font "Duplicate.ttf"
          font "Duplicate.ttf"
        end
      RUBY
      original_contents = caskfile.read
      json_caskfile = caskfile.sub_ext(".json")
      migrated_cask = instance_double(
        Cask::Cask,
        version:        "1.0",
        artifacts_list: [{ font: ["Duplicate.ttf"] }],
      )
      allow(Cask::CaskLoader).to receive(:load_from_installed_caskfile)
        .with(json_caskfile, api_fallback: false)
        .and_return(migrated_cask)

      error = T.let(nil, T.nilable(RuntimeError))
      begin
        described_class.migrate_caskfile_to_json(caskfile)
      rescue RuntimeError => e
        error = e
      end

      expect([error&.message, caskfile.read, json_caskfile.exist?]).to eq([
        "migrated Cask metadata differs from the original after preserving version and artifacts",
        original_contents,
        false,
      ])
    end

    it "uses API metadata when a Ruby caskfile contains a removed method" do
      token = "removed-method"
      caskfile = write_installed_caskfile(token, <<~RUBY)
        cask "#{token}" do
          version "1.0"
          appcast "https://example.com/appcast.xml"
          app "Old.app"
        end
      RUBY
      allow(Homebrew::API).to receive(:cask_token?).with(token).and_return(true)
      allow(Homebrew::API::Cask).to receive(:cask_json).with(token).and_return({
        "artifacts" => [{ "app" => ["Current.app"] }],
      })

      described_class.migrate_caskfile_to_json(caskfile)

      expect(JSON.parse(caskfile.sub_ext(".json").read)).to eq({
        "artifacts" => [{ "app" => ["Current.app"] }],
      })
    end

    it "uses API metadata when a Ruby caskfile contains a deprecated method" do
      token = "deprecated-method"
      caskfile = write_installed_caskfile(token, <<~RUBY)
        cask "#{token}" do
          version "1.0"
          app "Old.app"
        end
      RUBY
      allow(Cask::CaskLoader).to receive(:load)
        .with(caskfile, warn: false)
        .and_raise(MethodDeprecatedError.new)
      allow(Homebrew::API).to receive(:cask_token?).with(token).and_return(true)
      allow(Homebrew::API::Cask).to receive(:cask_json).with(token).and_return({
        "artifacts" => [{ "app" => ["Current.app"] }],
      })

      described_class.migrate_caskfile_to_json(caskfile)

      expect(JSON.parse(caskfile.sub_ext(".json").read)).to eq({
        "artifacts" => [{ "app" => ["Current.app"] }],
      })
    end

    it "uses tap metadata instead of the API for a receipt-less third-party cask", :trust_store do
      token = "third-party"
      tap = Tap.fetch("thirdparty", "foo")
      caskfile = write_installed_caskfile(token, "{}", extension: "json")
      cask_path = tap.cask_dir/"#{token}.rb"
      cask_path.dirname.mkpath
      cask_path.write <<~RUBY
        cask "#{token}" do
          version "2.0"
          app "Third Party.app"
        end
      RUBY
      Homebrew::Trust.trust!(:tap, tap.name)
      allow(Homebrew::EnvConfig).to receive(:no_install_from_api?).and_return(false)
      allow(Homebrew::API).to receive_messages(cask_token?: false, cask_renames: {})
      allow(Homebrew::API::Cask).to receive(:cask_json).and_raise("unexpected official API lookup")

      described_class.migrate_caskfile_to_json(caskfile)

      expect(JSON.parse(caskfile.read)).to eq({
        "artifacts" => [{ "app" => ["Third Party.app"] }],
      })
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "preserves artifacts when the install receipt is empty" do
      token = "empty-receipt"
      caskfile = write_installed_caskfile(token, <<~RUBY)
        cask "#{token}" do
          version "1.0"
          app "Empty Receipt.app"
        end
      RUBY
      (caskroom/token/".metadata/INSTALL_RECEIPT.json").write("")

      described_class.migrate_caskfile_to_json(caskfile)

      expect(JSON.parse(caskfile.sub_ext(".json").read)).to eq({
        "artifacts" => [{ "app" => ["Empty Receipt.app"] }],
      })
    end

    it "replaces malformed installed JSON using API metadata" do
      token = "malformed-json"
      caskfile = write_installed_caskfile(token, "{", extension: "json")
      allow(Homebrew::API).to receive(:cask_token?).with(token).and_return(true)
      allow(Homebrew::API::Cask).to receive(:cask_json).with(token).and_return({
        "artifacts" => [{ "app" => ["Current.app"] }],
      })

      described_class.migrate_caskfile_to_json(caskfile)

      expect(JSON.parse(caskfile.read)).to eq({
        "artifacts" => [{ "app" => ["Current.app"] }],
      })
    end

    it "replaces invalid artifact data in installed JSON using API metadata" do
      token = "invalid-artifacts"
      caskfile = write_installed_caskfile(token, JSON.generate({ "artifacts" => ["invalid"] }), extension: "json")
      allow(Homebrew::API).to receive(:cask_token?).with(token).and_return(true)
      allow(Homebrew::API::Cask).to receive(:cask_json).with(token).and_return({
        "artifacts" => [{ "app" => ["Current.app"] }],
      })

      described_class.migrate_caskfile_to_json(caskfile)

      expect(JSON.parse(caskfile.read)).to eq({
        "artifacts" => [{ "app" => ["Current.app"] }],
      })
    end

    it "keeps intentional empty artifacts in installed JSON" do
      caskfile = write_installed_caskfile("stage-only", JSON.generate({ "artifacts" => [] }), extension: "json")
      expect(Homebrew::API::Cask).not_to receive(:cask_json)

      described_class.migrate_caskfile_to_json(caskfile)

      expect(JSON.parse(caskfile.read)).to eq({ "artifacts" => [] })
    end

    it "does not mark unavailable artifacts as intentionally empty" do
      token = "removed-cask"
      caskfile = write_installed_caskfile(token, "{}", extension: "json")
      allow(Homebrew::API).to receive(:cask_token?).with(token).and_return(false)
      allow(Homebrew::API::Cask).to receive(:cask_json).with(token).and_raise(
        ErrorDuringExecution.new(["curl"], status: 22),
      )

      described_class.migrate_caskfile_to_json(caskfile)

      expect(JSON.parse(caskfile.read)).to eq({})
    end
  end

  describe ".corrupt_cask_dirs" do
    it "returns tokens for directories without valid caskfiles" do
      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:path).and_return(Pathname(dir))
        (Pathname(dir)/"corrupt-cask"/"1.0").mkpath
        casks_dir = (Pathname(dir)/"installed-cask"/".metadata"/"1.0"/"0"/"Casks")
        casks_dir.mkpath
        FileUtils.touch casks_dir/"installed-cask.rb"

        expect(described_class.corrupt_cask_dirs).to eq(["corrupt-cask"])
      end
    end

    it "returns empty array when all directories have valid caskfiles" do
      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:path).and_return(Pathname(dir))
        casks_dir = (Pathname(dir)/"installed-cask"/".metadata"/"1.0"/"0"/"Casks")
        casks_dir.mkpath
        FileUtils.touch casks_dir/"installed-cask.rb"

        expect(described_class.corrupt_cask_dirs).to be_empty
      end
    end

    it "returns empty array when caskroom is empty" do
      Dir.mktmpdir do |dir|
        allow(described_class).to receive(:path).and_return(Pathname(dir))

        expect(described_class.corrupt_cask_dirs).to be_empty
      end
    end
  end
end
