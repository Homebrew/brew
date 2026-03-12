# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-zap"

RSpec.describe Homebrew::DevCmd::GenerateZap do
  subject(:generate_zap) { described_class.new(["test"]) }

  it_behaves_like "parseable arguments"

  describe "#resolve_app_name_from_cask" do
    it "resolves app name from a cask with an app artifact" do
      app = instance_double(Cask::Artifact::App, target: Pathname.new("TestCask.app"))
      allow(app).to receive(:is_a?).with(Cask::Artifact::App).and_return(true)
      cask = instance_double(Cask::Cask, artifacts: [app])
      allow(Cask::CaskLoader).to receive(:load).with("test-cask").and_return(cask)

      expect(generate_zap.send(:resolve_app_name_from_cask, "test-cask")).to eq("TestCask")
    end

    it "falls back to title-cased token when no app artifact exists" do
      cask = Cask::Cask.new("test-cask")

      allow(Cask::CaskLoader).to receive(:load).with("test-cask").and_return(cask)

      expect(generate_zap.send(:resolve_app_name_from_cask, "test-cask")).to eq("Test Cask")
    end
  end

  describe "#scan_directories" do
    it "finds matching entries case-insensitively" do
      Dir.mktmpdir do |tmpdir|
        FileUtils.mkdir_p("#{tmpdir}/Library/Preferences")
        FileUtils.touch("#{tmpdir}/Library/Preferences/com.example.Foo.plist")
        FileUtils.touch("#{tmpdir}/Library/Preferences/com.example.app.plist")

        allow(Dir).to receive(:home).and_return(tmpdir)

        results = generate_zap.send(:scan_directories, ["Library/Preferences"],
                                    home_relative: true, pattern: "foo")

        expect(results.size).to eq(1)
        expect(results.first).to include("com.example.Foo.plist")
      end
    end

    it "returns empty array when directory does not exist" do
      results = generate_zap.send(:scan_directories, ["nonexistent/path"],
                                  home_relative: true, pattern: "test")
      expect(results).to be_empty
    end
  end

  describe "#scan_home_root" do
    it "finds dotfiles matching the pattern" do
      Dir.mktmpdir do |tmpdir|
        FileUtils.touch("#{tmpdir}/.foo")
        FileUtils.touch("#{tmpdir}/.bar")
        FileUtils.touch("#{tmpdir}/foo")

        allow(Dir).to receive(:home).and_return(tmpdir)

        results = generate_zap.send(:scan_home_root, "foo")

        expect(results.size).to eq(1)
        expect(results.first).to include(".foo")
      end
    end
  end

  describe "#collapse_to_wildcards" do
    it "collapses entries sharing a common basename prefix" do
      paths = [
        "~/Library/Application Scripts/com.example.foo",
        "~/Library/Application Scripts/com.example.foo.plist",
      ]
      result = generate_zap.send(:collapse_to_wildcards, paths)

      expect(result).to eq(["~/Library/Application Scripts/com.example.foo*"])
    end

    it "collapses multiple groups in the same directory independently" do
      paths = [
        "~/Library/Preferences/com.example.foo",
        "~/Library/Preferences/com.example.foo.plist",
        "~/Library/Preferences/com.example.app.plist",
      ]
      result = generate_zap.send(:collapse_to_wildcards, paths)

      expect(result).to include("~/Library/Preferences/com.example.foo*")
      expect(result).to include("~/Library/Preferences/com.example.app.plist")
      expect(result.size).to eq(2)
    end

    it "leaves single entries unchanged" do
      paths = ["~/Library/Caches/com.example.foo"]
      result = generate_zap.send(:collapse_to_wildcards, paths)

      expect(result).to eq(paths)
    end

    it "does not collapse entries in different directories" do
      paths = [
        "~/Library/Caches/com.example.foo",
        "~/Library/Preferences/com.example.foo.plist",
      ]
      result = generate_zap.send(:collapse_to_wildcards, paths)

      expect(result).to eq(paths)
    end

    it "leaves unrelated entries in the same directory as-is" do
      paths = [
        "~/Library/Preferences/com.example.app.plist",
        "~/Library/Preferences/com.example.foo.plist",
      ]
      result = generate_zap.send(:collapse_to_wildcards, paths)

      expect(result).to eq(paths)
    end
  end

  describe "#normalize_path" do
    it "replaces home directory with ~" do
      home = Dir.home
      expect(generate_zap.send(:normalize_path, "#{home}/Library/Preferences/com.example.foo.plist"))
        .to eq("~/Library/Preferences/com.example.foo.plist")
    end

    it "leaves system paths unchanged" do
      expect(generate_zap.send(:normalize_path, "/Library/Preferences/com.example.foo.plist"))
        .to eq("/Library/Preferences/com.example.foo.plist")
    end
  end

  describe "#format_stanza" do
    it "formats a single trash path as inline" do
      output = generate_zap.send(:format_stanza,
                                 trash:  ["~/Library/Preferences/com.example.foo.plist"],
                                 delete: [],
                                 rmdir:  [])
      expect(output).to eq('zap trash: "~/Library/Preferences/com.example.foo.plist"')
    end

    it "formats multiple trash paths as an array" do
      output = generate_zap.send(:format_stanza,
                                 trash:  [
                                   "~/Library/Caches/com.example.foo",
                                   "~/Library/Preferences/com.example.foo.plist",
                                 ],
                                 delete: [],
                                 rmdir:  [])
      expect(output).to include("zap trash: [")
      expect(output).to include('"~/Library/Caches/com.example.foo"')
      expect(output).to include('"~/Library/Preferences/com.example.foo.plist"')
    end

    it "includes multiple directive types" do
      output = generate_zap.send(:format_stanza,
                                 trash:  ["~/Library/Preferences/com.example.foo.plist"],
                                 delete: ["/Library/Preferences/com.example.foo.plist"],
                                 rmdir:  ["~/Library/Application Support/Foo"])
      expect(output).to include("trash:")
      expect(output).to include("delete:")
      expect(output).to include("rmdir:")
    end
  end

  describe "#replace_uuids" do
    it "replaces UUIDs with wildcards" do
      paths = [
        "~/Library/Application Support/CrashReporter/Foo_1BBE8750-D851-5930-A16F-BE4B820B4537.plist",
      ]
      result = generate_zap.send(:replace_uuids, paths)

      expect(result).to eq(["~/Library/Application Support/CrashReporter/Foo_*.plist"])
    end

    it "deduplicates paths that only differed by UUID" do
      paths = [
        "~/Library/Caches/com.example.foo/Data_1BBE8750-D851-5930-A16F-BE4B820B4537",
        "~/Library/Caches/com.example.foo/Data_AABBCCDD-1122-3344-5566-778899AABBCC",
      ]
      result = generate_zap.send(:replace_uuids, paths)

      expect(result).to eq(["~/Library/Caches/com.example.foo/Data_*"])
    end

    it "leaves paths without UUIDs unchanged" do
      paths = ["~/Library/Preferences/com.example.foo.plist"]
      result = generate_zap.send(:replace_uuids, paths)

      expect(result).to eq(paths)
    end
  end

  describe "#derive_rmdir_candidates" do
    it "suggests Application Support parent directories" do
      paths = ["~/Library/Application Support/Foo/config.json"]
      result = generate_zap.send(:derive_rmdir_candidates, paths)
      expect(result).to include("~/Library/Application Support/Foo")
    end

    it "does not suggest rmdir for Preferences" do
      paths = ["~/Library/Preferences/com.example.foo.plist"]
      result = generate_zap.send(:derive_rmdir_candidates, paths)
      expect(result).to be_empty
    end

    it "does not suggest rmdir for CrashReporter" do
      paths = ["~/Library/Application Support/CrashReporter/Foo_ABC123.plist"]
      result = generate_zap.send(:derive_rmdir_candidates, paths)
      expect(result).to be_empty
    end

    it "does not suggest rmdir for system-level shared directories" do
      paths = ["/Library/Application Support/Foo"]
      result = generate_zap.send(:derive_rmdir_candidates, paths)
      expect(result).to be_empty
    end
  end
end
