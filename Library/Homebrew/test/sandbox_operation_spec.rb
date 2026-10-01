# typed: true
# frozen_string_literal: true

require "sandbox"
require "unpack_strategy"
require "patch"
require "formula_installer"

RSpec.describe Sandbox do
  let(:sandbox) { described_class.new }
  let(:archive) { TEST_FIXTURE_DIR/"cask/container.tar.gz" }

  before do
    brew_file = mktmpdir/"brew"
    brew_file.write("")
    brew_file.chmod(0400)
    ENV["HOMEBREW_BREW_FILE"] = brew_file.to_s
    allow(described_class).to receive_messages(new: sandbox, isolate_operation?: true)
    allow(sandbox).to receive(:sandbox_command) { |args, _tmpdir| args }
    allow(sandbox).to receive(:apply_before_exec?).and_return(false)
  end

  it "extracts archives in a separate process using its private temporary directory" do
    temporary_directory = mktmpdir
    directory = mktmpdir
    HOMEBREW_TEMP.chmod(0555)

    UnpackStrategy::Tar.new(archive, temporary_directory:).extract(to: directory)

    expect(directory/"container").to be_a_file
  ensure
    HOMEBREW_TEMP.chmod(0755)
  end

  it "mounts nested disk images in the parent and copies their contents in a worker", :needs_macos do
    mount = UnpackStrategy::Dmg::Mount.new(mktmpdir)
    (mount.path/"container").mkpath
    (mount.path/"container/file").write("contents")
    (mount.path/"Applications").make_symlink("/Applications")
    image = UnpackStrategy::Dmg.new(TEST_FIXTURE_DIR/"cask/container.dmg")
    allow(image).to receive(:mount).and_yield([mount])
    allow(UnpackStrategy::Dmg).to receive(:new).and_return(image)
    archive = mktmpdir/"nested.tar"
    system "tar", "-cf", archive.to_s, "-C", (TEST_FIXTURE_DIR/"cask").to_s, "container.dmg"
    directory = mktmpdir

    UnpackStrategy::Tar.new(archive).extract_nestedly(to: directory, prioritize_extension: true)

    expect((directory/"container/file").read).to eq("contents")
  end

  it "preserves a lone symlink instead of extracting its target" do
    source = mktmpdir
    target = mktmpdir/"target"
    target.write("outside")
    (source/"link").make_symlink(target)
    directory = mktmpdir

    UnpackStrategy::Directory.new(source).extract_nestedly(to: directory)

    expect(directory/"link").to be_a_symlink
  end

  it "rejects an extraction directory replaced with a symlink before granting access" do
    strategy = UnpackStrategy::Tar.new(archive)
    outside = mktmpdir
    (outside/"first").write("")
    (outside/"second").write("")
    allow(strategy).to receive(:extract) do |to:, **|
      to.rmdir
      to.make_symlink(outside)
    end

    expect { strategy.extract_nestedly(to: mktmpdir) }.to raise_error(/Extraction directory is a symlink/)
  end

  it "isolates patch validation" do
    directory = mktmpdir
    (directory/"file").write("before\n")
    expect(sandbox).to receive(:capture).and_call_original

    Patch.ensure_targets_within!("--- file\n+++ file\n@@ -1 +1 @@\n-before\n+after\n", strip: :p0, base: directory)
  end

  it "rejects a patch directory symlink before granting write access" do
    directory = mktmpdir
    outside = mktmpdir
    (outside/"file").write("before\n")
    (directory/"subdir").make_symlink(outside)
    patch = StringPatch.new(:p0, "--- file\n+++ file\n@@ -1 +1 @@\n-before\n+after\n")
    patch.directory = "subdir"

    expect { directory.cd { patch.apply } }.to raise_error(/Patch directory escapes the staged source tree/)
  end

  it "isolates local VCS repository inspection" do
    strategy = GitDownloadStrategy.new("https://example.com/repo.git", "repo", Version.new("1"))
    expect(sandbox).to receive(:capture).and_call_original

    strategy.ref?
  end

  it "keeps local VCS inspection offline" do
    strategy = GitDownloadStrategy.new("https://example.com/repo.git", "repo", Version.new("1"))
    strategy.ref?

    expect(sandbox.profile.rules).to include(have_attributes(allow: false, operation: "network*", filter: nil))
  end

  it "rejects a VCS download symlink before granting write access" do
    strategy = GitDownloadStrategy.new("https://example.com/repo.git", "repo", Version.new("1"))
    strategy.cached_location.make_symlink(mktmpdir)

    expect { strategy.ref? }.to raise_error(/VCS download path is a symlink/)
  end

  it "isolates bottle relocation" do
    path = HOMEBREW_CELLAR/"sandbox-test/1"
    path.mkpath
    (path/"file").write("@@HOMEBREW_PREFIX@@/bin\n")
    expect(sandbox).to receive(:capture).and_call_original

    Keg.new(path).replace_placeholders_with_locations([Pathname("file")], skip_linkage: true)
  end

  it "repairs install linkage in the sandbox without failing the installation" do
    formula = formula("sandbox-test") do
      T.bind(self, T.class_of(Formula))
      url "foo-1.0"
    end
    formula.prefix.mkpath
    (formula.prefix/"target").write("")
    link = formula.prefix/"link"
    link.make_symlink(formula.prefix/"target")

    FormulaInstaller.new(formula).fix_dynamic_linkage(Keg.new(formula.prefix))

    expect([link.readlink.to_s, Homebrew.failed?]).to eq(["target", false])
  end
end
