# typed: true
# frozen_string_literal: true

RSpec.describe Cask::Config, :cask do
  subject(:config) { described_class.new }

  describe "#initialize" do
    it "defines all instance variables in a consistent order" do
      configs = [
        described_class.new,
        described_class.new(default: {}, env: {}, explicit: {}),
      ]

      expect(configs.map(&:instance_variables)).to all(eq([
        :@default,
        :@env,
        :@explicit,
        :@binarydir,
        :@manpagedir,
        :@bash_completion,
        :@zsh_completion,
        :@fish_completion,
      ]))
    end
  end

  describe "::from_json" do
    let(:invalid_keys_json) do
      <<~EOS
        {
          "default": {},
          "env": {
            "appdir": "/path/to/apps",
            "invaliddir": "/path/to/invalid"
          },
          "explicit": {}
        }
      EOS
    end

    let(:legacy_keys_json) do
      <<~EOS
        {
          "default": {},
          "env": {
            "input-methoddir": "/path/to/input/methods"
          },
          "explicit": {}
        }
      EOS
    end

    it "deserializes a configuration in JSON format" do
      config = described_class.from_json <<~EOS
        {
          "default": {
            "appdir": "/path/to/apps"
          },
          "env": {},
          "explicit": {}
        }
      EOS
      expect(config.appdir).to eq(Pathname("/path/to/apps"))
    end

    it "ignores invalid keys when requested" do
      config = described_class.from_json(invalid_keys_json, ignore_invalid_keys: true)

      expect(config.env).to eq(appdir: Pathname("/path/to/apps"))
    end

    it "warns about ignored invalid keys" do
      expect { described_class.from_json(invalid_keys_json, ignore_invalid_keys: true) }
        .to output(/Ignoring unknown cask configuration keys: \[:invaliddir\]/).to_stderr
    end

    it "does not warn when all keys are valid" do
      valid_json = { default: {}, env: { appdir: "/path/to/apps" }, explicit: {} }.to_json

      expect { described_class.from_json(valid_json, ignore_invalid_keys: true) }
        .not_to output.to_stderr
    end

    it "normalizes hyphenated keys from a saved configuration" do
      config = described_class.from_json(legacy_keys_json, ignore_invalid_keys: true)

      expect(config.env).to eq(input_methoddir: Pathname("/path/to/input/methods"))
      expect(config.input_methoddir).to eq(Pathname("/path/to/input/methods"))
    end

    it "does not warn about hyphenated keys from a saved configuration" do
      expect { described_class.from_json(legacy_keys_json, ignore_invalid_keys: true) }
        .not_to output.to_stderr
    end

    it "accepts hyphenated keys from a saved configuration without ignoring invalid keys" do
      config = described_class.from_json(legacy_keys_json)

      expect(config.input_methoddir).to eq(Pathname("/path/to/input/methods"))
    end
  end

  describe "#default" do
    it "returns the default directories" do
      expect(config.default[:appdir]).to eq(Pathname(TEST_TMPDIR).join("cask-appdir"))
    end
  end

  describe "#appdir" do
    it "returns the default value if no HOMEBREW_CASK_OPTS is unset" do
      expect(config.appdir).to eq(Pathname(TEST_TMPDIR).join("cask-appdir"))
    end

    specify "environment overwrites default" do
      ENV["HOMEBREW_CASK_OPTS"] = "--appdir=/path/to/apps"

      expect(config.appdir).to eq(Pathname("/path/to/apps"))
    end

    specify "specific overwrites default" do
      config = described_class.new(explicit: { appdir: "/explicit/path/to/apps" })

      expect(config.appdir).to eq(Pathname("/explicit/path/to/apps"))
    end

    specify "explicit overwrites environment" do
      ENV["HOMEBREW_CASK_OPTS"] = "--appdir=/path/to/apps"

      config = described_class.new(explicit: { appdir: "/explicit/path/to/apps" })

      expect(config.appdir).to eq(Pathname("/explicit/path/to/apps"))
    end
  end

  describe "#env" do
    it "returns directories specified with the HOMEBREW_CASK_OPTS variable" do
      ENV["HOMEBREW_CASK_OPTS"] = "--appdir=/path/to/apps"

      expect(config.env).to eq(appdir: Pathname("/path/to/apps"))
    end

    it "normalizes hyphenated option names to underscored keys" do
      ENV["HOMEBREW_CASK_OPTS"] = "--input-methoddir=/path/to/input/methods"

      expect(config.env).to eq(input_methoddir: Pathname("/path/to/input/methods"))
      expect(config.input_methoddir).to eq(Pathname("/path/to/input/methods"))
    end

    it "accepts underscored option names" do
      ENV["HOMEBREW_CASK_OPTS"] = "--input_methoddir=/path/to/input/methods"

      expect(config.env).to eq(input_methoddir: Pathname("/path/to/input/methods"))
    end

    it "normalizes option names but not their values" do
      ENV["HOMEBREW_CASK_OPTS"] = "--language=zh-TW,en-GB"

      expect(config.env).to eq(languages: ["zh-TW", "en-GB"])
    end

    it "survives a JSON round-trip" do
      ENV["HOMEBREW_CASK_OPTS"] = "--input-methoddir=/path/to/input/methods"

      round_tripped = described_class.from_json(config.to_json)

      expect(round_tripped.input_methoddir).to eq(Pathname("/path/to/input/methods"))
    end
  end

  describe "#explicit" do
    let(:config) do
      described_class.new(explicit: { appdir:    "/explicit/path/to/apps",
                                      languages: ["zh-TW", "en"] })
    end

    it "returns directories explicitly given as arguments" do
      expect(config.explicit[:appdir]).to eq(Pathname("/explicit/path/to/apps"))
    end

    it "returns array of preferred languages" do
      expect(config.explicit[:languages]).to eq(["zh-TW", "en"])
    end
  end

  context "when installing a cask and then adding a global default dir" do
    let(:config) do
      json = <<~EOS
        {
          "default": {
            "appdir": "/default/path/before/adding/fontdir"
          },
          "env": {},
          "explicit": {}
        }
      EOS
      described_class.from_json(json)
    end

    describe "#appdir" do
      it "honors metadata of the installed cask" do
        expect(config.appdir).to eq(Pathname("/default/path/before/adding/fontdir"))
      end
    end

    describe "#fontdir" do
      it "falls back to global default on incomplete metadata" do
        expect(config.default).to include(fontdir: Pathname(TEST_TMPDIR).join("cask-fontdir"))
      end
    end
  end
end
