# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/pr-upload"

class PrUploadForTesting < Homebrew::DevCmd::PrUpload
  sig { override.returns(Homebrew::CLI::Parser) }
  def self.parser = Homebrew::DevCmd::PrUpload.parser

  sig { params(json_files: T::Array[String]).returns(T::Hash[String, T.anything]) }
  def merge_bottle_metadata(json_files) = bottles_hash_from_json_files(json_files, args)
end

RSpec.describe Homebrew::DevCmd::PrUpload do
  before do
    formula_path.dirname.mkpath
    formula_path.write(formula_source)
    Formulary.enable_factory_cache!
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
      .to include(:bottles_hash_from_json_files)
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
