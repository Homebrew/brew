# typed: true
# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API::Cask::CaskStructGenerator do
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
      { pkg:        ["arg1", "arg2"] },
      { uninstall:  ["arg1", "arg2", { kwarg1: "value1" }] },
      { stage_only: [{ kwarg1: "value1" }] },
      {
        target:         "$HOMEBREW_PREFIX/share/zsh/site-functions/_foo",
        zsh_completion: ["$APPDIR/Foo.app/Contents/Resources/completions/zsh/_foo"],
      },
      {
        zsh_completion: ["$APPDIR/Bar.app/Contents/Resources/completions/zsh/_bar"],
        target:         "$HOMEBREW_PREFIX/share/zsh/site-functions/_bar",
      },
      {
        target: "/Applications/Bar.app",
        app:    ["Foo.app", { target: "Bar.app" }],
      },
    ]
    expected_output = [
      [:preflight, [], {}, Homebrew::API::CaskStruct::EMPTY_BLOCK],
      [:pkg, ["arg1", "arg2"], {}, nil],
      [:uninstall, ["arg1", "arg2"], { kwarg1: "value1" }, nil],
      [:stage_only, [], { kwarg1: "value1" }, nil],
      [:zsh_completion, ["$APPDIR/Foo.app/Contents/Resources/completions/zsh/_foo"], {}, nil],
      [:zsh_completion, ["$APPDIR/Bar.app/Contents/Resources/completions/zsh/_bar"], {}, nil],
      [:app, ["Foo.app"], { target: "Bar.app" }, nil],
    ]
    output = described_class.process_artifacts(input)
    expect(output).to eq expected_output
  end

  it "rejects unknown artifact keys" do
    input = [
      { system: ["/usr/bin/true"] },
      { instance_eval: ["raise 'unexpected dispatch'"] },
    ]

    expect(described_class.process_artifacts(input)).to be_empty
  end

  it "rejects artifacts without a DSL key" do
    expect(described_class.process_artifacts([{ target: "/Applications/Foo.app" }])).to be_empty
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

  it "drops the deprecated verified URL spec from existing metadata" do
    output = described_class.process_url_specs({ verified: "cdn.example.com/", bar: "baz" })
    expect(output).to eq({ bar: "baz" })
  end
end
