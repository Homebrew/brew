# frozen_string_literal: true

describe Cask::Config, :cask do
  subject(:config) { described_class.new }

  describe "::from_json" do
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

    it "returns string of explicit config keys and values" do
      expect(config.explicit_s).to eq('appdir: "/explicit/path/to/apps", language: "zh-TW,en"')
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
