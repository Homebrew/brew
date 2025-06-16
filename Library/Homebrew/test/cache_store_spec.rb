# frozen_string_literal: true

require "cache_store"

RSpec.describe CacheStoreDatabase do
  subject(:sample_db) { described_class.new(:sample) }

  describe "self.use" do
    let(:type) { :test }

    it "creates a new `DatabaseCache` instance" do
      cache_store = instance_double(described_class, "cache_store", write_if_dirty!: nil)
      expect(described_class).to receive(:new).with(type).and_return(cache_store)
      expect(cache_store).to receive(:write_if_dirty!)
      described_class.use(type) do |_db|
        # do nothing
      end
    end
  end

  describe "#set" do
    let(:db) { instance_double(Hash, "db", :[]= => nil) }

    it "sets the value in the `CacheStoreDatabase`" do
      allow(File).to receive(:write)
      allow(sample_db).to receive_messages(created?: true, db:)

      expect(db).to receive(:has_key?).with(:foo).and_return(false)
      expect(db).not_to have_key(:foo)
      sample_db.set(:foo, "bar")
    end
  end

  describe "#get" do
    context "with a database created" do
      let(:db) { instance_double(Hash, "db", :[] => "bar") }

      it "gets value in the `CacheStoreDatabase` corresponding to the key" do
        expect(db).to receive(:has_key?).with(:foo).and_return(true)
        allow(sample_db).to receive_messages(created?: true, db:)
        expect(db).to have_key(:foo)
        expect(sample_db.get(:foo)).to eq("bar")
      end
    end

    context "without a database created" do
      let(:db) { instance_double(Hash, "db", :[] => nil) }

      before do
        allow(sample_db).to receive_messages(created?: false, db:)
      end

      it "does not get value in the `CacheStoreDatabase` corresponding to key" do
        expect(sample_db.get(:foo)).not_to be("bar")
      end

      it "does not call `db[]` if `CacheStoreDatabase.created?` is `false`" do
        expect(db).not_to receive(:[])
        sample_db.get(:foo)
      end
    end
  end

  describe "#delete" do
    context "with a database created" do
      let(:db) { instance_double(Hash, "db", :[] => { foo: "bar" }) }

      before do
        allow(sample_db).to receive_messages(created?: true, db:)
      end

      it "deletes value in the `CacheStoreDatabase` corresponding to the key" do
        expect(db).to receive(:delete).with(:foo)
        sample_db.delete(:foo)
      end
    end

    context "without a database created" do
      let(:db) { instance_double(Hash, "db", delete: nil) }

      before do
        allow(sample_db).to receive_messages(created?: false, db:)
      end

      it "does not call `db.delete` if `CacheStoreDatabase.created?` is `false`" do
        expect(db).not_to receive(:delete)
        sample_db.delete(:foo)
      end
    end
  end

  describe "#write_if_dirty!" do
    context "with an open database" do
      it "does not raise an error when `close` is called on the database" do
        expect { sample_db.write_if_dirty! }.not_to raise_error(NoMethodError)
      end
    end

    context "without an open database" do
      before do
        sample_db.instance_variable_set(:@db, nil)
      end

      it "does not raise an error when `close` is called on the database" do
        expect { sample_db.write_if_dirty! }.not_to raise_error(NoMethodError)
      end
    end
  end

  describe "#created?" do
    let(:cache_path) { Pathname("path/to/homebrew/cache/sample.json") }

    before do
      allow(sample_db).to receive(:cache_path).and_return(cache_path)
    end

    context "when `cache_path.exist?` returns `true`" do
      before do
        allow(cache_path).to receive(:exist?).and_return(true)
      end

      it "returns `true`" do
        expect(sample_db.created?).to be(true)
      end
    end

    context "when `cache_path.exist?` returns `false`" do
      before do
        allow(cache_path).to receive(:exist?).and_return(false)
      end

      it "returns `false`" do
        expect(sample_db.created?).to be(false)
      end
    end
  end
end
