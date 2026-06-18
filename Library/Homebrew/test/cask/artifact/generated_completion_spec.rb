# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::GeneratedCompletion, :cask do
  let(:staged_path) { Pathname(Dir.mktmpdir) }

  let(:cask) do
    tmp_staged = staged_path
    Cask::Cask.new("test-generated-completion") do
      version "1.0"
      sha256 :no_check
      url "file:///dev/null"
      generate_completions_from_executable "bin/foo", "completions"
      instance_variable_set(:@staged_path, tmp_staged)
    end
  end

  let(:bash_dir) { cask.config.bash_completion }
  let(:zsh_dir) { cask.config.zsh_completion }
  let(:fish_dir) { cask.config.fish_completion }

  before do
    (staged_path/"bin").mkpath
    (staged_path/"bin/foo").write("#!/bin/sh\necho \"$SHELL completion\"")
    (staged_path/"bin/foo").chmod(0755)
  end

  after do
    FileUtils.rm_rf(staged_path)
  end

  describe "#install_phase" do
    it "generates completion scripts for default shells" do
      artifact = cask.artifacts.grep(described_class).first

      allow(Sandbox).to receive_messages(ensure_sandbox_installed!: nil, available?: true)
      allow(Sandbox).to receive(:new) do
        instance_double(Sandbox).tap do |sandbox|
          allow(sandbox).to receive(:allow_read)
          allow(sandbox).to receive(:allow_write_temp_and_cache)
          allow(sandbox).to receive(:deny_read_home)
          allow(sandbox).to receive(:deny_all_network)
          allow(sandbox).to receive(:run) do |*args|
            Pathname(args.fetch(7)).write("#{args.grep(/^SHELL=/).first.delete_prefix("SHELL=")} completion output")
          end
        end
      end

      artifact.install_phase

      expect(bash_dir/"foo").to be_a_file
      expect((bash_dir/"foo").read).to eq("bash completion output")
      expect(zsh_dir/"_foo").to be_a_file
      expect((zsh_dir/"_foo").read).to eq("zsh completion output")
      expect(fish_dir/"foo.fish").to be_a_file
      expect((fish_dir/"foo.fish").read).to eq("fish completion output")
    end

    it "sandboxes completion generation without network access" do
      artifact = cask.artifacts.grep(described_class).first
      sandboxes = []
      calls = []
      homes = []

      allow(Sandbox).to receive_messages(ensure_sandbox_installed!: nil, available?: true)
      allow(Sandbox).to receive(:new) do
        instance_double(Sandbox).tap do |sandbox|
          expect(sandbox).to receive(:allow_read).with(path: staged_path, type: :subpath)
          expect(sandbox).to receive(:allow_write_temp_and_cache)
          expect(sandbox).to receive(:deny_read_home)
          expect(sandbox).to receive(:deny_all_network) { calls << :deny_all_network }
          allow(sandbox).to receive(:run) do |*args|
            calls << :run
            homes << Pathname(args.grep(/^HOME=/).first.delete_prefix("HOME="))
            Pathname(args.fetch(7)).write("completion")
          end
          sandboxes << sandbox
        end
      end

      artifact.install_phase

      expect(sandboxes.length).to eq(3)
      expect(calls).to eq([:deny_all_network, :run, :deny_all_network, :run, :deny_all_network, :run])
      expect(homes.uniq.length).to eq(3)
      expect(homes).to all(satisfy { |home| !home.exist? })
    end

    context "when generation fails for one shell" do
      it "warns and continues generating other shells" do
        artifact = cask.artifacts.grep(described_class).first

        allow(Sandbox).to receive_messages(ensure_sandbox_installed!: nil, available?: true)
        allow(Sandbox).to receive(:new) do
          instance_double(Sandbox).tap do |sandbox|
            allow(sandbox).to receive(:allow_read)
            allow(sandbox).to receive(:allow_write_temp_and_cache)
            allow(sandbox).to receive(:deny_read_home)
            allow(sandbox).to receive(:deny_all_network)
            allow(sandbox).to receive(:run) do |*args|
              raise "boom" if args.include?("SHELL=bash")

              Pathname(args.fetch(7)).write("zsh completion")
            end
          end
        end

        expect { artifact.install_phase }
          .to output(/Failed to generate bash completions/).to_stderr

        expect(zsh_dir/"_foo").to be_a_file
      end
    end
  end

  describe "#uninstall_phase" do
    it "removes generated completion scripts" do
      artifact = cask.artifacts.grep(described_class).first

      bash_dir.mkpath
      zsh_dir.mkpath
      fish_dir.mkpath
      (bash_dir/"foo").write("bash")
      (zsh_dir/"_foo").write("zsh")
      (fish_dir/"foo.fish").write("fish")

      artifact.uninstall_phase(command: NeverSudoSystemCommand)

      expect(bash_dir/"foo").not_to exist
      expect(zsh_dir/"_foo").not_to exist
      expect(fish_dir/"foo.fish").not_to exist
    end
  end

  context "with specific shells and format" do
    let(:cask) do
      tmp_staged = staged_path
      Cask::Cask.new("test-generated-completion") do
        version "1.0"
        sha256 :no_check
        url "file:///dev/null"
        generate_completions_from_executable "bin/foo", "completions",
                                             shells: [:zsh], shell_parameter_format: :arg, base_name: "bar"
        instance_variable_set(:@staged_path, tmp_staged)
      end
    end

    it "generates only for the specified shell with the correct format" do
      artifact = cask.artifacts.grep(described_class).first
      captured_args = T.let([], T::Array[String])

      allow(Sandbox).to receive_messages(ensure_sandbox_installed!: nil, available?: true)
      allow(Sandbox).to receive(:new) do
        instance_double(Sandbox).tap do |sandbox|
          allow(sandbox).to receive(:allow_read)
          allow(sandbox).to receive(:allow_write_temp_and_cache)
          allow(sandbox).to receive(:deny_read_home)
          allow(sandbox).to receive(:deny_all_network)
          allow(sandbox).to receive(:run) do |*args|
            captured_args = args.map(&:to_s)
            Pathname(args.fetch(7)).write("zsh completion")
          end
        end
      end

      artifact.install_phase

      expect(captured_args).to include("--shell=zsh")
      expect(captured_args.fetch(5)).to end_with(" 2>/dev/null")
      expect(zsh_dir/"_bar").to be_a_file
      expect(bash_dir/"bar").not_to exist
      expect(fish_dir/"bar.fish").not_to exist
    end
  end

  context "with string shells" do
    let(:cask) do
      tmp_staged = staged_path
      Cask::Cask.new("test-generated-completion") do
        version "1.0"
        sha256 :no_check
        url "file:///dev/null"
        generate_completions_from_executable "bin/foo", "completions",
                                             shells: %w[bash zsh fish pwsh]
        instance_variable_set(:@staged_path, tmp_staged)
      end
    end

    it "normalizes shells to symbols" do
      artifact = cask.artifacts.grep(described_class).first

      expect(artifact.shells).to eq([:bash, :zsh, :fish, :pwsh])
    end
  end
end
