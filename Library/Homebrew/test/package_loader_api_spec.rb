# typed: strict
# frozen_string_literal: true

require "formula"
require "cask/cask_loader"

RSpec.describe Formulary, :no_api do
  it "restricts explicit formula tap paths to registered formula files" do
    path = CoreTap.instance.path/"payload.rb"
    path.dirname.mkpath
    path.write 'raise "Unregistered formula evaluated"'

    expect { described_class.from_tap_path(path) }.to raise_error(FormulaUnavailableError)
  ensure
    path&.unlink
  end

  it "restricts explicit cask tap paths to registered cask files" do
    path = CoreCaskTap.instance.path/"payload.rb"
    path.dirname.mkpath
    path.write 'raise "Unregistered cask evaluated"'

    expect { Cask::CaskLoader.from_tap_path(path) }.to raise_error(Cask::CaskUnavailableError)
  end

  it "loads registered formula files for tap audits" do
    path = CoreTap.instance.new_formula_path("path-loading")
    path.dirname.mkpath
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
      end
    RUBY

    (path.dirname/"path-loading").mkpath
    (path.dirname/"path-loading/nested.rb").write 'raise "Unselected formula evaluated"'
    allow(CoreTap.instance.formula_files).to receive(:include?).and_raise("Linear formula search")
    allow(CoreTap.instance.formula_files).to receive(:sort_by).and_raise("Repeated formula sort")

    expect(described_class.from_tap_path(path).name).to eq("path-loading")
  end

  it "loads registered cask files for tap audits" do
    path = CoreCaskTap.instance.new_cask_path("path-loading")
    path.dirname.mkpath
    path.write <<~RUBY
      cask "path-loading" do
        version "1.0"
        sha256 :no_check
        url "https://example.com/path-loading-1.0.zip"
      end
    RUBY

    (path.dirname/"path-loading").mkpath
    (path.dirname/"path-loading/nested.rb").write 'raise "Unselected cask evaluated"'
    allow(CoreCaskTap.instance.cask_files).to receive(:include?).and_raise("Linear cask search")
    allow(CoreCaskTap.instance.cask_files).to receive(:sort_by).and_raise("Repeated cask sort")

    expect(Cask::CaskLoader.from_tap_path(path).token).to eq("path-loading")
  end

  it "loads registered formula and cask files from symlinked CI checkouts" do
    tap = Tap.fetch("homebrew", "path-loading")
    tap.path.parent.mkpath
    tap.path.make_symlink(mktmpdir)
    formula_path = tap.path.realpath/"Formula/path-loading.rb"
    formula_path.dirname.mkpath
    formula_path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
      end
    RUBY
    cask_path = tap.path.realpath/"Casks/path-loading.rb"
    cask_path.dirname.mkpath
    cask_path.write <<~RUBY
      cask "path-loading" do
        version "1.0"
        sha256 :no_check
        url "https://example.com/path-loading-1.0.zip"
      end
    RUBY

    allow(CoreTap.instance).to receive(:formula_files).and_raise("Scanned an unrelated tap")
    allow(CoreCaskTap.instance).to receive(:cask_files).and_raise("Scanned an unrelated tap")

    expect([
      described_class.from_tap_path(formula_path).full_name,
      Cask::CaskLoader.from_tap_path(cask_path).full_name,
    ]).to eq(["#{tap}/path-loading", "#{tap}/path-loading"])
  ensure
    tap&.path&.unlink
  end

  it "loads an explicitly selected formula despite the implicit path policy" do
    ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
    path = mktmpdir/"path-loading.rb"
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
      end
    RUBY

    expect(described_class.from_path(path).name).to eq("path-loading")
  end

  it "resolves an explicitly selected source file" do
    path = mktmpdir/"path-loading.rb"
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
      end
    RUBY

    expect(described_class.resolve_from_path(path).version.to_s).to eq("1.0")
  end

  it "loads explicitly supplied cask source" do
    expect(Cask::CaskLoader.from_content(<<~RUBY).token).to eq("path-loading")
      cask "path-loading" do
        version "1.0"
        sha256 :no_check
        url "https://example.com/path-loading-1.0.zip"
      end
    RUBY
  end

  it "loads an explicitly selected bottle" do
    ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = "1"
    allow(Utils::Bottles).to receive(:formula_contents).and_return <<~RUBY
      class TestballBottle < Formula
        url "https://example.com/testball_bottle-0.1.tar.gz"
      end
    RUBY

    expect(described_class.from_bottle(
             TEST_FIXTURE_DIR/"bottles/testball_bottle-0.1.#{Utils::Bottles.tag}.bottle.tar.gz",
           )).to be_a(Formula)
  end
end
