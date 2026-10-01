# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Bzip2 do
  subject(:path) { TEST_FIXTURE_DIR/"cask/container.bz2" }

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: ["container"]

  it "extracts with bzip2" do
    strategy = described_class.new(path)

    Dir.mktmpdir do |dir|
      unpack_dir = Pathname(dir)
      target = unpack_dir/path.basename
      expect(strategy).to receive(:system_command!).with(
        "bzip2",
        args:    ["-q", "-d", target],
        env:     { "PATH" => an_instance_of(String) },
        verbose: false,
      )

      strategy.extract(to: unpack_dir)
    end
  end

  it "adds Homebrew bzip2 to PATH without resolving a formula" do
    strategy = described_class.new(path)

    Dir.mktmpdir do |dir|
      unpack_dir = Pathname(dir)
      target = unpack_dir/path.basename
      expect(Formula).not_to receive(:[])
      expect(strategy).to receive(:system_command!).with(
        "bzip2",
        args:    ["-q", "-d", target],
        env:     Utils::Path.formula_opt_bin_env("bzip2", ORIGINAL_PATHS),
        verbose: false,
      )

      strategy.extract(to: unpack_dir)
    end
  end
end
