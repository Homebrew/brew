# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/pr-upload"

class PrUploadForTesting < Homebrew::DevCmd::PrUpload
  sig { override.returns(Homebrew::CLI::Parser) }
  def self.parser = Homebrew::DevCmd::PrUpload.parser

  sig { params(bottles_hash: T::Hash[String, T.anything]).void }
  def validate_transition_bottles!(bottles_hash) = check_transition_bottles!(bottles_hash)

  sig { params(json_files: T::Array[String]).returns(T::Hash[String, T.anything]) }
  def merge_bottle_metadata(json_files) = bottles_hash_from_json_files(json_files, args)
end

RSpec.describe Homebrew::DevCmd::PrUpload do
  before do
    formula_path.dirname.mkpath
    formula_path.write(formula_source)
    Formulary.enable_factory_cache!
    allow_any_instance_of(BottleTransition).to receive(:required?).and_return(true)
  end

  sig {
    returns(T::Hash[String, {
      "formula" => T::Hash[String, String],
      "bottle"  => { "root_url" => String, "rebuild" => Integer, "tags" => T::Hash[String, T::Hash[String, String]] },
    }])
  }
  let(:bottles) do
    {
      current.name => {
        "formula" => { "path" => current.path.relative_path_from(HOMEBREW_REPOSITORY).to_s, "pkg_version" => "2.0" },
        "bottle"  => {
          "root_url" => current.bottle_specification.root_url,
          "rebuild"  => 0,
          "tags"     => { "arm64_golden_gate" => { "sha256" => "a" * 64 } },
        },
      },
    }
  end

  sig { returns(Formula) }
  def current
    Formulary.factory(formula_path)
  end

  sig { returns(String) }
  def formula_source
    <<~RUBY
      class TransitionTest < Formula
        url "https://brew.sh/transition-test-2.0.tar.gz"
        bottle do
          sha256 arm64_golden_gate: "#{"a" * 64}"
        end
      end
    RUBY
  end
  sig { returns(Pathname) }
  def formula_path
    CoreTap.instance.path/"Formula/t/transition-test.rb"
  end

  it_behaves_like "parseable arguments"

  it "keeps upload helpers private" do
    expect(described_class.private_instance_methods)
      .to include(:check_transition_bottles!, :bottles_hash_from_json_files)
  end

  describe "#check_transition_bottles!" do
    it "rejects metadata for a different package version in upload-only mode" do
      bottles.fetch(current.name).fetch("formula")["pkg_version"] = "1.0"

      expect do
        PrUploadForTesting.new(["--upload-only"]).validate_transition_bottles!(bottles)
      end.to raise_error(UsageError, /metadata does not match/)
    end

    it "rejects a different rebuild when keeping old bottles" do
      bottles.fetch(current.name).fetch("bottle")["rebuild"] = 1

      expect do
        PrUploadForTesting.new(["--keep-old", "--upload-only"]).validate_transition_bottles!(bottles)
      end.to raise_error(UsageError, /metadata does not match/)
    end

    it "rejects a bottle commit that omits the transition platform" do
      bottles
      formula_path.atomic_write(formula_source.sub("arm64_golden_gate", "arm64_tahoe"))

      expect do
        PrUploadForTesting.new([]).validate_transition_bottles!(bottles)
      end.to raise_error(UsageError, /before publishing or merging/)
    end

    it "reloads retained coverage from disk when keeping old bottles" do
      bottles.fetch(current.name).fetch("bottle")["tags"] = { "arm64_tahoe" => { "sha256" => "a" * 64 } }
      formula_path.atomic_write(formula_source.sub("arm64_golden_gate", "arm64_tahoe"))
      Formulary.clear_cache
      Formulary.factory(formula_path)
      formula_path.atomic_write(formula_source.sub("bottle do", "bottle do\n    sha256 arm64_tahoe: \"#{"a" * 64}\""))

      expect do
        PrUploadForTesting.new(["--keep-old"]).validate_transition_bottles!(bottles)
      end.not_to raise_error
    end

    it "identifies missing upload artifacts separately from committed coverage" do
      bottles.fetch(current.name).fetch("bottle")["tags"] = { "arm64_tahoe" => {} }

      expect do
        PrUploadForTesting.new(["--upload-only"]).validate_transition_bottles!(bottles)
      end.to raise_error(UsageError, /upload set is missing/)
    end

    it "normalises the registry organisation before comparing URLs" do
      bottles.fetch(current.name).fetch("bottle")["root_url"] = "https://ghcr.io/v2/Homebrew/core"

      expect { PrUploadForTesting.new([]).validate_transition_bottles!(bottles) }.not_to raise_error
    end

    it "skips a formula that is not enrolled" do
      allow_any_instance_of(BottleTransition).to receive(:required?).and_return(false)
      bottles.fetch(current.name).fetch("bottle")["tags"] = {}

      expect { PrUploadForTesting.new([]).validate_transition_bottles!(bottles) }.not_to raise_error
    end

    context "when the formula belongs to another tap" do
      it "does not apply the core transition policy" do
        stub_const("HOMEBREW_MACOS_NEWEST_SUPPORTED", "26")
        allow(current).to receive(:tap).and_return(Tap.fetch("user/test"))
        allow(Formulary).to receive(:factory).with(current.path).and_return(current)
        allow_any_instance_of(BottleTransition).to receive(:required?).and_call_original
        bottles.fetch(current.name).fetch("bottle")["tags"] = {}

        expect { PrUploadForTesting.new([]).validate_transition_bottles!(bottles) }.not_to raise_error
      end
    end
  end

  describe "#bottles_hash_from_json_files" do
    it "accepts equivalent registry URLs across platform records" do
      directory = mktmpdir
      first_json = directory/"first.bottle.json"
      second_json = directory/"second.bottle.json"
      first_json.write(JSON.generate(bottles))
      bottles.fetch(current.name).fetch("bottle")["root_url"] = "https://ghcr.io/v2/Homebrew/homebrew-core"
      second_json.write(JSON.generate(bottles))
      command = PrUploadForTesting.new([])

      expect do
        command.merge_bottle_metadata([first_json.to_s, second_json.to_s])
      end.not_to raise_error
    end

    it "rejects mixed package versions before their tag sets can be merged" do
      directory = mktmpdir
      old_json = directory/"old.bottle.json"
      new_json = directory/"new.bottle.json"
      new_json.write(JSON.generate(bottles))
      bottles.fetch(current.name).fetch("formula")["pkg_version"] = "1.0"
      old_json.write(JSON.generate(bottles))
      command = PrUploadForTesting.new([])

      expect do
        command.merge_bottle_metadata([old_json.to_s, new_json.to_s])
      end.to raise_error(UsageError, /Inconsistent bottle metadata/)
    end
  end
end
