# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"

RSpec.describe Homebrew::Bundle do
  context "when the system call succeeds" do
    it "omits all stdout output if verbose is false" do
      expect { described_class.system "echo", "foo", verbose: false }.not_to output.to_stdout_from_any_process
    end

    it "emits all stdout output if verbose is true" do
      expect { described_class.system "echo", "foo", verbose: true }.to output("foo\n").to_stdout_from_any_process
    end
  end

  context "when the system call fails" do
    it "emits all stdout output even if verbose is false" do
      expect do
        described_class.system "/bin/bash", "-c", "echo foo && false",
                               verbose: false
      end.to output("foo\n").to_stdout_from_any_process
    end

    it "emits all stdout output only once if verbose is true" do
      expect do
        described_class.system "/bin/bash", "-c", "echo foo && true",
                               verbose: true
      end.to output("foo\n").to_stdout_from_any_process
    end
  end

  context "when running npm" do
    let(:npm) { mktmpdir/"npm" }

    before do
      stub_const("HOMEBREW_PREFIX", mktmpdir)
      node = HOMEBREW_PREFIX/"opt/node/bin/node"
      node.dirname.mkpath
      node.write "#!/bin/sh\nexit 0\n"
      node.chmod 0755
      npm.write "#!/usr/bin/env node\n"
      npm.chmod 0755
      ENV["PATH"] = npm.dirname.to_s
      allow(Homebrew::Bundle::Npm).to receive(:package_manager_executable).and_return(npm)
    end

    test_each([false, true]) do |verbose|
      it "finds node with verbose: #{verbose}" do
        expect(described_class.system(npm.to_s, "--version", verbose:)).to be true
      end
    end
  end

  context "when checking for homebrew/cask", :needs_macos do
    it "finds it when present" do
      allow(File).to receive(:directory?).with("#{HOMEBREW_PREFIX}/Caskroom").and_return(true)
      allow(File).to receive(:directory?)
        .with("#{HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-cask")
        .and_return(true)
      expect(described_class.cask_installed?).to be(true)
    end
  end

  describe ".mark_as_installed_on_request!", :no_api do
    subject(:mark_installed!) { described_class.mark_as_installed_on_request!(entries) }

    let(:brewfile_content) { "brew 'myformula'" }
    let(:entries) { dsl.entries }
    let(:dsl) { Homebrew::Bundle::Dsl.new(Pathname.new("/fake/Brewfile")) }
    let(:tabfile) { Pathname.new("/fake/INSTALL_RECEIPT.json") }

    before do
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_content)
      allow(tabfile).to receive_messages(blank?: false, exist?: true)
    end

    context "when formula is installed but not marked as installed_on_request" do
      let(:tab) { instance_double(Tab, installed_on_request: false, tabfile:) }

      before do
        allow(Formula).to receive(:installed_formula_names).and_return(["myformula"])
        allow(Tab).to receive(:for_name).with("myformula").and_return(tab)
      end

      it "sets installed_on_request=true and writes" do
        expect(tab).to receive(:installed_on_request=).with(true)
        expect(tab).to receive(:write)
        mark_installed!
      end
    end

    context "when formula is not installed" do
      let(:brewfile_content) { "brew 'notinstalled'" }

      before do
        allow(Formula).to receive(:installed_formula_names).and_return([])
      end

      it "skips the formula" do
        expect(Tab).not_to receive(:for_name)
        mark_installed!
      end
    end

    context "when formula is already marked as installed_on_request" do
      let(:brewfile_content) { "brew 'alreadymarked'" }
      let(:tab) { instance_double(Tab, installed_on_request: true, tabfile:) }

      before do
        allow(Formula).to receive(:installed_formula_names).and_return(["alreadymarked"])
        allow(Tab).to receive(:for_name).with("alreadymarked").and_return(tab)
      end

      it "skips writing" do
        expect(tab).not_to receive(:installed_on_request=)
        expect(tab).not_to receive(:write)
        mark_installed!
      end
    end
  end

  describe ".mark_as_installed_on_request! with formula names", :no_api do
    after do
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"testuser"
    end

    %w[deno deno-alias deno-old homebrew/core/deno testuser/testtap/deno].each do |name|
      it "marks the installed receipt for #{name}" do
        T.bind(self, RSpec::Core::ExampleGroup)
        tap = name.start_with?("testuser/") ? Tap.fetch("testuser/testtap") : CoreTap.instance
        formula_path = tap.new_formula_path("deno")
        formula_path.dirname.mkpath
        formula_path.write <<~RUBY
          class Deno < Formula
            url "https://brew.sh/deno-1.0.tar.gz"
          end
        RUBY
        (tap.path/"Aliases").mkpath
        (tap.path/"Aliases/deno-alias").make_symlink(formula_path)
        (tap.path/"formula_renames.json").write JSON.generate("deno-old" => "deno")
        tap.clear_cache
        receipt = HOMEBREW_CELLAR/"deno/1.0"/AbstractTab::FILENAME
        receipt.dirname.mkpath
        tab = Tab.empty
        tab.tabfile = receipt
        tab.write

        described_class.mark_as_installed_on_request!([Homebrew::Bundle::Dsl::Entry.new(:brew, name)])

        expect(JSON.parse(receipt.read).fetch("installed_on_request")).to be(true)
      end
    end
  end
end
