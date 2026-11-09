# typed: strict
# frozen_string_literal: true

RSpec.describe Cask::CaskLoader, :cask do
  describe "::load_from_name" do
    test_each([
      ".", "..", "./local-transmission.rb", "file:///tmp/local-transmission.rb", 'cask "token" do end'
    ]) do |name|
      it "rejects #{name.inspect} as an invalid token" do
        expect { described_class.load_from_name(name) }
          .to raise_error(Cask::CaskUnavailableError, /Invalid cask token/)
      end
    end

    it "does not load a token-shaped file in the current directory" do
      source = mktmpdir/"cache-name.rb"
      source.write 'cask "cache-name" do end'

      expect do
        source.dirname.cd { described_class.load_from_name(source.basename.to_s) }
      end.to raise_error(Cask::CaskUnavailableError)
    end

    context "when using a tap", :no_api do
      test_each(%w[app-name@1.2+3 app_name app.rb app.json .app LOCAL-TRANSMISSION]) do |name|
        it "loads the token #{name.inspect}" do
          path = CoreCaskTap.instance.cask_dir/"#{name.downcase}.rb"
          path.write "cask #{name.downcase.inspect} do end" unless path.exist?

          expect(described_class.load_from_name(name).token).to eq(name.downcase)
        end
      end

      it "resolves renames without warnings when requested" do
        allow(CoreCaskTap.instance).to receive(:cask_renames).and_return("old-transmission" => "local-transmission")

        expect do
          expect(described_class.load_from_name("old-transmission", warn: false).token).to eq("local-transmission")
        end.not_to output.to_stderr
      end

      it "warns about renames by default" do
        allow(CoreCaskTap.instance).to receive(:cask_renames).and_return("old-transmission" => "local-transmission")

        expect { described_class.load_from_name("old-transmission") }
          .to output(/old-transmission was renamed to local-transmission/).to_stderr
      end

      it "requires explicit installed metadata loading for a removed cask" do
        path = Cask::Caskroom.path/"removed-cask/.metadata/1.0/20250101000000.000/Casks/removed-cask.rb"
        path.dirname.mkpath
        path.write 'cask "removed-cask" do version "1.0" end'

        expect { described_class.load_from_name("removed-cask") }.to raise_error(Cask::CaskUnavailableError)
      end
    end

    context "when using the API" do
      before do
        cask_json = described_class.load("local-transmission").to_hash_with_variations
        cask_struct = Homebrew::API::Cask::CaskStructGenerator.generate_cask_struct_hash(cask_json)
        allow(Homebrew::API).to receive(:cask_token?).with("local-transmission").and_return(true)
        allow(Homebrew::API::Internal).to receive(:cask_hash).with("local-transmission")
                                                             .and_return(cask_struct.serialize)
      end

      it "prefers the API to a tapped cask" do
        expect(described_class.load_from_name("local-transmission").loaded_from_api?).to be true
      end
    end

    it "raises the existing unavailable error for an unknown token" do
      expect { described_class.load_from_name("removed-cask") }
        .to raise_error(Cask::CaskUnavailableError, /No Cask with this name exists/)
    end
  end
end
