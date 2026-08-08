# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::GeneratedCompletion, :cask do
  let(:staged_path) { Pathname(Dir.mktmpdir) }

  let(:cask) do
    Cask::Cask.new("test-generated-completion") do
      version "1.0"
      sha256 :no_check
      url "file:///dev/null"
      generate_completions_from_executable "bin/foo", "completions"
    end
  end

  let(:bash_dir) { cask.config.bash_completion }
  let(:zsh_dir) { cask.config.zsh_completion }
  let(:fish_dir) { cask.config.fish_completion }
  let(:run_sandboxed_payload) do
    proc { |args| Utils.safe_fork { exec(*args.map(&:to_s)) } }
  end

  before do
    allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
    allow(cask).to receive(:staged_path).and_return(staged_path)
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

      allow(Sandbox).to receive(:available?).and_return(true)
      allow(Sandbox).to receive(:new) do
        instance_double(Sandbox).tap do |sandbox|
          allow(sandbox).to receive(:allow_read)
          allow(sandbox).to receive(:add_install_hook_rules)
          allow(sandbox).to receive(:allow_write_path)
          allow(sandbox).to receive(:run) do |*args|
            run_sandboxed_payload.call(args)
          end
        end
      end

      artifact.install_phase

      expect(bash_dir/"foo").to be_a_file
      expect((bash_dir/"foo").read).to eq("bash completion\n")
      expect(zsh_dir/"_foo").to be_a_file
      expect((zsh_dir/"_foo").read).to eq("zsh completion\n")
      expect(fish_dir/"foo.fish").to be_a_file
      expect((fish_dir/"foo.fish").read).to eq("fish completion\n")
    end

    it "sandboxes completion generation without network access" do
      artifact = cask.artifacts.grep(described_class).first
      sandboxes = []
      calls = []
      homes = []

      allow(Sandbox).to receive(:available?).and_return(true)
      allow(Sandbox).to receive(:new) do
        instance_double(Sandbox).tap do |sandbox|
          allow(sandbox).to receive(:allow_read)
          expect(sandbox).to receive(:allow_read).with(path: staged_path, type: :subpath)
          expect(sandbox).to receive(:add_install_hook_rules).with(network_access_allowed: false) do
            calls << :add_install_hook_rules
          end
          allow(sandbox).to receive(:allow_write_path)
          allow(sandbox).to receive(:run) do |*args|
            calls << :run
            homes << Pathname(args.grep(/^HOME=/).first.delete_prefix("HOME="))
            run_sandboxed_payload.call(args)
          end
          sandboxes << sandbox
        end
      end

      artifact.install_phase

      expect(sandboxes.length).to eq(1)
      expect(calls).to eq([:add_install_hook_rules, :run])
      expect(homes.uniq.length).to eq(1)
      expect(homes).to all(satisfy { |home| !home.exist? })
    end

    context "when generation fails for one shell" do
      it "warns and continues generating other shells" do
        artifact = cask.artifacts.grep(described_class).first
        (staged_path/"bin/foo").write <<~SH
          #!/bin/sh
          [ "$SHELL" = bash ] && exit 1
          echo "$SHELL completion"
        SH

        allow(Sandbox).to receive(:available?).and_return(true)
        allow(Sandbox).to receive(:new) do
          instance_double(Sandbox).tap do |sandbox|
            allow(sandbox).to receive(:allow_read)
            allow(sandbox).to receive(:add_install_hook_rules)
            allow(sandbox).to receive(:allow_write_path)
            allow(sandbox).to receive(:run) do |*args|
              run_sandboxed_payload.call(args)
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
      Cask::Cask.new("test-generated-completion") do
        version "1.0"
        sha256 :no_check
        url "file:///dev/null"
        generate_completions_from_executable "bin/foo", "completions",
                                             shells: [:zsh], shell_parameter_format: :arg, base_name: "bar"
      end
    end

    it "generates only for the specified shell with the correct format" do
      artifact = cask.artifacts.grep(described_class).first
      captured_payload = T.let({}, T::Hash[String, T.untyped])

      allow(Sandbox).to receive(:available?).and_return(true)
      allow(Sandbox).to receive(:new) do
        instance_double(Sandbox).tap do |sandbox|
          allow(sandbox).to receive(:allow_read)
          allow(sandbox).to receive(:add_install_hook_rules)
          allow(sandbox).to receive(:allow_write_path)
          allow(sandbox).to receive(:run) do |*args|
            captured_payload = JSON.parse(Pathname(args.last).read)
            run_sandboxed_payload.call(args)
          end
        end
      end

      artifact.install_phase

      expect(captured_payload.fetch("completions").fetch(0).fetch("shell_parameter")).to eq("--shell=zsh")
      expect(zsh_dir/"_bar").to be_a_file
      expect(bash_dir/"bar").not_to exist
      expect(fish_dir/"bar.fish").not_to exist
    end
  end

  context "with string shells" do
    let(:cask) do
      Cask::Cask.new("test-generated-completion") do
        version "1.0"
        sha256 :no_check
        url "file:///dev/null"
        generate_completions_from_executable "bin/foo", "completions",
                                             shells: %w[bash zsh fish pwsh]
      end
    end

    it "normalizes shells to symbols" do
      artifact = cask.artifacts.grep(described_class).first

      expect(artifact.shells).to eq([:bash, :zsh, :fish, :pwsh])
    end
  end
end
