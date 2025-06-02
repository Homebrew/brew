# frozen_string_literal: true

RSpec.describe Cask::CaskLoader::FromTapLoader do
  let(:tap) { CoreCaskTap.instance }
  let(:cask_name) { "testball" }
  let(:cask_full_name) { "homebrew/cask/#{cask_name}" }
  let(:cask_path) { tap.cask_dir/"#{cask_name}.rb" }

  describe "#load" do
    before do
      cask_path.parent.mkpath
      cask_path.write <<~RUBY
        cask '#{cask_name}' do
          url 'https://brew.sh/'
        end
      RUBY
    end

    it "returns a Cask" do
      expect(described_class.new(cask_full_name).load(config: nil)).to be_a(Cask::Cask)
    end

    it "raises an error if the Cask cannot be found" do
      expect { described_class.new("foo/bar/baz").load(config: nil) }.to raise_error(Cask::CaskUnavailableError)
    end

    context "with sharded Cask directory" do
      let(:cask_path) { tap.cask_dir/cask_name[0]/"#{cask_name}.rb" }

      it "returns a Cask" do
        expect(described_class.new(cask_full_name).load(config: nil)).to be_a(Cask::Cask)
      end
    end
  end
end
