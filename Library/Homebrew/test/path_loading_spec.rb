# typed: strict
# frozen_string_literal: true

require "formula"
require "cask/cask_loader"

RSpec.describe Formulary, :no_api do
  test_each([nil, "1"]) do |forbid_paths|
    context "with HOMEBREW_FORBID_PACKAGES_FROM_PATHS=#{forbid_paths.inspect}" do
      before do
        ENV["HOMEBREW_FORBID_PACKAGES_FROM_PATHS"] = forbid_paths
        ENV["HOMEBREW_DEVELOPER"] = "1"
      end

      it "rejects formula paths in the Cellar without evaluating them" do
        path = HOMEBREW_CELLAR/"path-loading/1.0/payload.rb"
        path.dirname.mkpath
        path.write 'raise "Formula path evaluated"'

        expect { Formulary.factory(path.to_s) }.to raise_error(FormulaUnavailableError)
      end

      it "rejects formula paths in taps without evaluating them" do
        path = CoreTap.instance.new_formula_path("path-loading")
        path.dirname.mkpath
        path.write 'raise "Formula path evaluated"'

        expect { Formulary.resolve(path.to_s) }.to raise_error(FormulaUnavailableError)
      end

      it "rejects cask paths in the Caskroom without evaluating them" do
        path = Cask::Caskroom.path/"path-loading/1.0/payload.rb"
        path.dirname.mkpath
        path.write 'raise "Cask path evaluated"'

        expect { Cask::CaskLoader.load(path.to_s) }.to raise_error(Cask::CaskUnavailableError)
      end

      it "rejects cask paths in taps without evaluating them" do
        path = CoreCaskTap.instance.new_cask_path("path-loading")
        path.dirname.mkpath
        path.write 'raise "Cask path evaluated"'

        expect { Cask::CaskLoader.load(path.to_s) }.to raise_error(Cask::CaskUnavailableError)
      end
    end
  end

  it "does not reuse an explicitly loaded formula path from the factory cache" do
    path = mktmpdir/"path-loading.rb"
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
      end
    RUBY
    described_class.enable_factory_cache!
    described_class.from_path(path)

    expect { described_class.factory(path.to_s) }.to raise_error(FormulaUnavailableError)
  end

  it "does not grant path loading to dependencies of an explicitly loaded formula" do
    path = mktmpdir/"path-loading.rb"
    dependency = path.dirname/"dependency.rb"
    dependency.write 'raise "Dependency path evaluated"'
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
        depends_on #{dependency.to_s.inspect}
      end
    RUBY

    expect { described_class.from_path(path).deps.fetch(0).to_formula }
      .to raise_error(FormulaUnavailableError)
  end

  it "rejects a relative path to a formula in a tap" do
    path = CoreTap.instance.new_formula_path("path-loading")
    path.dirname.mkpath
    path.write 'raise "Formula path evaluated"'

    path.dirname.cd do
      expect { Formulary.factory("./path-loading.rb") }.to raise_error(FormulaUnavailableError)
    end
  end

  it "rejects a cask JSON path" do
    path = mktmpdir/"path-loading.json"
    path.write '{"token":"path-loading"}'

    expect { Cask::CaskLoader.load(path.to_s) }.to raise_error(Cask::CaskUnavailableError)
  end

  it "rejects bottle paths during ordinary formula lookup" do
    expect { described_class.factory((TEST_FIXTURE_DIR/"bottles/testball_bottle-0.1.#{Utils::Bottles.tag}.bottle.tar.gz").to_s) }
      .to raise_error(FormulaUnavailableError)
  end

  it "rejects cask source during ordinary lookup" do
    expect { Cask::CaskLoader.load('cask "payload" do; raise "Cask content evaluated"; end') }
      .to raise_error(Cask::CaskUnavailableError)
  end

  it "does not fall back to a keg's Ruby file during ordinary lookup" do
    path = HOMEBREW_CELLAR/"path-loading/1.0/.brew/path-loading.rb"
    path.dirname.mkpath
    path.write 'raise "Installed formula evaluated"'
    (HOMEBREW_PREFIX/"opt").mkpath
    (HOMEBREW_PREFIX/"opt/path-loading").make_symlink(path.dirname.parent)

    expect { described_class.factory("path-loading") }.to raise_error(FormulaUnavailableError)
  end

  it "does not fall back to an installed cask's Ruby file during ordinary lookup" do
    path = Cask::Caskroom.path/"path-loading/.metadata/1.0/20200101000000.000/Casks/path-loading.rb"
    path.dirname.mkpath
    path.write 'raise "Installed cask evaluated"'

    expect { Cask::CaskLoader.load("path-loading") }.to raise_error(Cask::CaskUnavailableError)
  end

  it "allows ordinary name lookup while evaluating a formula" do
    dependency = CoreTap.instance.new_formula_path("path-dependency")
    dependency.dirname.mkpath
    dependency.write <<~RUBY
      class PathDependency < Formula
        url "https://example.com/path-dependency-1.0.tar.gz"
      end
    RUBY
    path = mktmpdir/"path-loading.rb"
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
        version Formula["path-dependency"].version.to_s
      end
    RUBY

    expect(described_class.from_path(path).version.to_s).to eq("1.0")
  end

  it "does not interpret an internal path cache key as a formula name" do
    path = mktmpdir/"path-loading.rb"
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
      end
    RUBY
    described_class.enable_factory_cache!
    described_class.from_path(path)

    expect { described_class.factory("path:#{path}") }.to raise_error(FormulaUnavailableError)
  end

  it "rejects invalid names before looking up installed cask metadata" do
    allow(Cask::Cask).to receive(:new).and_raise("Invalid name reached metadata lookup")

    expect { Cask::CaskLoader.load_prefer_installed("../payload") }
      .to raise_error(Cask::CaskUnavailableError, /Invalid cask name/)
  end

  it "rejects paths through Formula[] inside formula hooks" do
    path = mktmpdir/"path-loading.rb"
    payload = path.dirname/"payload.rb"
    payload.write 'raise "Nested path evaluated"'
    path.write <<~RUBY
      class PathLoading < Formula
        url "https://example.com/path-loading-1.0.tar.gz"
        def install
          Formula[#{payload.to_s.inspect}]
        end
      end
    RUBY

    expect { described_class.from_path(path).install }.to raise_error(FormulaUnavailableError)
  end

  it "rejects implicit content loading inside cask definitions" do
    path = mktmpdir/"path-loading.rb"
    path.write <<~RUBY
      cask "path-loading" do
        ::Cask::CaskLoader.load('cask "payload" do; raise "Content evaluated"; end')
      end
    RUBY

    expect { Cask::CaskLoader.from_path(path) }.to raise_error(Cask::CaskUnavailableError)
  end
end
