# typed: strict
# frozen_string_literal: true

require "formula"
require "cask/cask_loader"
require "utils/path"

RSpec.describe Formulary, :no_api do
  test_each([nil, :payload, Pathname("payload.rb"), Cask::Cask.new("payload")]) do |ref|
    it "rejects non-string formula references: #{ref.inspect}" do
      expect { described_class.factory(ref) }.to raise_error(FormulaUnavailableError)
    end

    it "rejects non-string cask references: #{ref.inspect}" do
      expect { Cask::CaskLoader.load(ref) }.to raise_error(Cask::CaskUnavailableError)
    end

    it "rejects non-string references through Formula[]: #{ref.inspect}" do
      expect { Formula[ref] }.to raise_error(FormulaUnavailableError)
    end
  end

  test_each([:cached, Pathname("cached")]) do |ref|
    it "rejects non-string references even when the corresponding name is cached" do
      path = CoreTap.instance.new_formula_path("cached")
      path.dirname.mkpath
      path.write <<~RUBY
        class Cached < Formula
          url "https://example.com/cached-1.0.tar.gz"
        end
      RUBY
      described_class.enable_factory_cache!
      described_class.factory("cached")

      expect { described_class.factory(ref) }.to raise_error(FormulaUnavailableError)
    end
  end

  it "deprecates the old cask selector name" do
    expect { Cask::CaskLoader.for("missing") }.to raise_error(MethodDeprecatedError, /loader_for/)
  end

  it "deprecates the old path permission helper" do
    expect { Utils::Path.loadable_package_path?(Pathname("payload.rb"), :formula) }
      .to raise_error(MethodDeprecatedError, /from_path/)
  end

  test_each(["./payload.rb", "https://example.com/payload.rb", 'cask "payload" do; raise "evaluated"; end']) do |ref|
    it "warns about unsupported formula references: #{ref}" do
      ENV["HOMEBREW_DEVELOPER"] = "1"

      expect { described_class.loader_for(ref) }
        .to output(/Loading formulae from paths or URLs is not supported; use a formula name\./).to_stderr
    end

    it "warns about unsupported cask references: #{ref}" do
      ENV["HOMEBREW_DEVELOPER"] = "1"

      expect { Cask::CaskLoader.loader_for(ref) }
        .to output(/Loading casks from paths, URLs or Ruby source is not supported; use a cask name\./).to_stderr
    end

    it "does not warn about unsupported formula references when requested: #{ref}" do
      expect { described_class.loader_for(ref, warn: false) }.not_to output.to_stderr
    end

    it "does not warn about unsupported cask references when requested: #{ref}" do
      expect { Cask::CaskLoader.loader_for(ref, warn: false) }.not_to output.to_stderr
    end
  end

  it "deprecates the retired formula URL loader" do
    expect { Formulary::FromURILoader.new("file:///payload.rb") }
      .to raise_error(MethodDeprecatedError, /from_path/)
  end

  it "deprecates the retired cask URL loader" do
    expect { Cask::CaskLoader::FromURILoader.new("file:///payload.rb") }
      .to raise_error(MethodDeprecatedError, /from_path/)
  end

  it "deprecates the retired formula cache selector" do
    expect { Formulary::FromCacheLoader.try_new("payload") }
      .to raise_error(MethodDeprecatedError, /from_path/)
  end

  it "deprecates the retired installed formula selector" do
    expect { Formulary::FromKegLoader.try_new("payload") }
      .to raise_error(MethodDeprecatedError, /from_keg/)
  end

  it "deprecates the retired installed cask selector" do
    expect { Cask::CaskLoader::FromInstalledPathLoader.try_new("payload") }
      .to raise_error(MethodDeprecatedError, /load_from_installed_caskfile/)
  end

  it "deprecates the retired cask content selector" do
    expect { Cask::CaskLoader::FromContentLoader.try_new('cask "payload" do; end') }
      .to raise_error(MethodDeprecatedError, /from_content/)
  end

  it "deprecates the retired cask instance loader" do
    expect { Cask::CaskLoader::FromInstanceLoader.new(Cask::Cask.new("payload")) }
      .to raise_error(MethodDeprecatedError, /cask instance/)
  end

  it "rejects implicit paths without evaluating them" do
    path = mktmpdir/"payload.rb"
    path.write 'raise "evaluated"'

    expect { described_class.factory(path.to_s) }.to raise_error(FormulaUnavailableError)
  end

  it "keeps retired selectors disabled when deprecation notices are suppressed" do
    allow(described_class).to receive(:odeprecated)
    allow(Cask::CaskLoader).to receive(:odeprecated)
    allow(Utils::Path).to receive(:odeprecated)

    expect([
      Formulary::FromCacheLoader.try_new("payload"),
      Formulary::FromKegLoader.try_new("payload"),
      Cask::CaskLoader::FromInstalledPathLoader.try_new("payload"),
      Cask::CaskLoader::FromContentLoader.try_new('cask "payload" do; raise "evaluated"; end'),
      Utils::Path.loadable_package_path?(Pathname("payload.rb"), :formula),
    ]).to eq([nil, nil, nil, nil, false])
  end

  it "forwards deprecated name lookup to the secure selector" do
    allow(Cask::CaskLoader).to receive(:odeprecated)

    expect(Cask::CaskLoader.for("missing")).to be_a(Cask::CaskLoader::NullLoader)
  end

  it "deprecates the old formula path selector" do
    expect { Formulary::FromPathLoader.try_new("payload") }
      .to raise_error(MethodDeprecatedError, /Formulary.from_path/)
  end
end
