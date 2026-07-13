# typed: true
# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API::Cask::CaskStructGenerator do
  describe "::generate_cask_struct_hash" do
    it "passes explicit array defaults for keys absent from minimal installed caskfiles" do
      # `CaskStruct.from_hash` only applies prop defaults when runtime type
      # checking is enabled (it always is under RSpec, never for users), so
      # `nil` here means `nil` props in production and crashes cask loading.
      expect(Homebrew::API::CaskStruct).to receive(:from_hash)
        .with(hash_including("names" => [], "renames" => []), ignore_types: true)
        .and_call_original

      described_class.generate_cask_struct_hash({ "version" => "1.0" }, ignore_types: true)
    end
  end

  describe ":process_depends_on" do
    let(:depends_on_non_macos) do
      {
        arch:    [{ type: :intel, bits: 64 }],
        formula: ["foo"],
      }
    end
    let(:depends_on_linux) { { linux: LinuxRequirement.new } }
    let(:depends_on_macos_equals) { { macos: { :== => ["15"] } } }
    let(:depends_on_macos_greater) { { macos: MacOSRequirement.new([:sequoia], comparator: ">=") } }
    let(:depends_on_macos_bare) { { macos: MacOSRequirement.new([]) } }
    let(:depends_on_maximum_macos) { { maximum_macos: MacOSRequirement.new([:sequoia], comparator: "<=") } }

    specify :aggregate_failures do
      expect(
        described_class.process_depends_on(depends_on_non_macos),
      ).to eq({ arch: :intel, formula: ["foo"] })
      expect(
        described_class.process_depends_on(depends_on_linux),
      ).to eq({ linux: :any })
      expect(
        described_class.process_depends_on(depends_on_macos_equals),
      ).to eq({ macos: [:sequoia] })
      expect(
        described_class.process_depends_on(depends_on_macos_greater),
      ).to eq({ macos: :sequoia })
      expect(
        described_class.process_depends_on(depends_on_macos_bare),
      ).to eq({ macos: :any })
      expect(
        described_class.process_depends_on({ macos: {} }),
      ).to eq({ macos: :any })
      expect(
        described_class.process_depends_on(depends_on_maximum_macos),
      ).to eq({ maximum_macos: :sequoia })
    end
  end

  specify "::process_artifacts" do
    input = [
      { preflight: nil },
      { foo:       ["arg1", "arg2"] },
      { bar:       ["arg1", "arg2", { kwarg1: "value1" }] },
      { baz:       [{ kwarg1: "value1" }] },
    ]
    expected_output = [
      [:preflight, [], {}, Homebrew::API::CaskStruct::EMPTY_BLOCK],
      [:foo, ["arg1", "arg2"], {}, nil],
      [:bar, ["arg1", "arg2"], { kwarg1: "value1" }, nil],
      [:baz, [], { kwarg1: "value1" }, nil],
    ]
    output = described_class.process_artifacts(input)
    expect(output).to eq expected_output
  end

  specify "::process_url_specs" do
    input = {
      user_agent: ":fake",
      using:      "curl",
      foo:        nil,
      bar:        "baz",
    }
    expected_output = {
      user_agent: :fake,
      using:      :curl,
      bar:        "baz",
    }
    output = described_class.process_url_specs(input)
    expect(output).to eq expected_output
  end
end
