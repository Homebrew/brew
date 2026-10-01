# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AbstractArtifact, :cask do
  describe "#run_cask_sandbox" do
    subject(:artifact) do
      Cask::Artifact::PostflightSteps.new(cask, [{
        "type"    => "write",
        "path"    => { "base" => "staged_path", "path" => "output" },
        "content" => contents,
      }])
    end

    let(:cask) do
      Cask::Cask.new("sandbox-payload") do
        version "1.0"
        sha256 :no_check
        url "file:///dev/null"
      end
    end
    let(:sandbox) { instance_double(Sandbox).as_null_object }
    let(:contents) { "original" }

    before do
      allow(Sandbox).to receive_messages(new: sandbox, use_for?: true)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*args, **|
        Utils.safe_fork { exec(*args.map(&:to_s)) }
      end
    end

    it "stores payloads under var/homebrew/sandbox" do
      payload_paths = []
      allow(sandbox).to receive(:run) do |*args, **|
        payload_paths << Pathname(args.fetch(-2))
      end

      artifact.install_phase

      expect(payload_paths.map { |path| path.dirname.dirname }).to eq([HOMEBREW_PREFIX/"var/homebrew/sandbox"])
    end

    it "removes its temporary directory when the sandbox succeeds" do
      artifact.install_phase

      expect((HOMEBREW_PREFIX/"var/homebrew/sandbox").children).to be_empty
    end

    it "removes its temporary directory when the sandbox fails" do
      allow(sandbox).to receive(:run).and_raise("Sandbox failed")

      begin
        artifact.install_phase
      rescue RuntimeError => e
        raise if e.message != "Sandbox failed"
      else
        raise "Expected sandbox failure"
      end

      expect((HOMEBREW_PREFIX/"var/homebrew/sandbox").children).to be_empty
    end

    it "rejects a replaced payload before running its steps" do
      allow(sandbox).to receive(:run) do |*args, **|
        HOMEBREW_PREFIX.glob("var/homebrew/sandbox/*/payload.json").each do |path|
          path.binwrite(JSON.generate("action" => "generated_completions", "completions" => []))
        end
        Utils.safe_fork { exec(*args.map(&:to_s)) }
      end

      expect { artifact.install_phase }.to raise_error(RuntimeError, /Cask sandbox payload checksum mismatch/)
    end

    context "with a payload larger than the exec argument limit" do
      let(:contents) { "é" * (2 * 1024 * 1024) }

      it "writes the complete contents" do
        artifact.install_phase

        expect((cask.staged_path/"output").read).to eq(contents)
      end
    end

    it "parses the verified snapshot if the payload changes after reading" do
      tamper = mktmpdir/"tamper.rb"
      tamper.write <<~RUBY
        File.singleton_class.prepend(Module.new do
          def binread(path, *)
            super.tap do
              binwrite(path, '{"action":"generated_completions","completions":[]}') if basename(path) == "payload.json"
            end
          end
        end)
      RUBY
      allow(sandbox).to receive(:run) do |*args, **|
        args.insert(args.index("--") || raise("Missing Ruby argument separator"), "-r", tamper)
        Utils.safe_fork { exec(*args.map(&:to_s)) }
      end

      artifact.install_phase

      expect((cask.staged_path/"output").read).to eq(contents)
    end
  end

  describe "#sort_order" do
    it "includes generated and platform-specific artifacts" do
      sort_order = Cask::Artifact::App.allocate.sort_order

      expect(sort_order).to include(
        Cask::Artifact::CommandWrapper,
        Cask::Artifact::GeneratedScript,
        Cask::Artifact::PreflightSteps,
        Cask::Artifact::PostflightSteps,
        Cask::Artifact::UninstallPreflightSteps,
        Cask::Artifact::UninstallPostflightSteps,
      )
      expect(sort_order.fetch(Cask::Artifact::AppImage)).to eq(sort_order.fetch(Cask::Artifact::App))
      expect(sort_order.fetch(Cask::Artifact::GeneratedCompletion))
        .to be_between(
          sort_order.fetch(Cask::Artifact::PwshCompletion),
          sort_order.fetch(Cask::Artifact::PostflightSteps),
        ).exclusive
    end
  end

  describe ".read_script_arguments" do
    let(:stanza) { :installer }

    it "accepts a string and uses it as the executable" do
      arguments = "something"

      expect(described_class.read_script_arguments(arguments, stanza)).to eq(["something", {}])
    end

    it "accepts a hash with an executable" do
      arguments = { executable: "something" }

      expect(described_class.read_script_arguments(arguments, stanza)).to eq(["something", {}])
    end

    it "does not mutate the original arguments in place" do
      arguments = { executable: "something" }
      clone = arguments.dup

      described_class.read_script_arguments(arguments, stanza)

      expect(arguments).to eq(clone)
    end
  end
end
