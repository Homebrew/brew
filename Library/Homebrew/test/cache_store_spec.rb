# typed: true
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

    it "releases the refcount when the block breaks" do
      cache_store = instance_double(described_class, "cache_store", write_if_dirty!: nil)
      allow(described_class).to receive(:new).with(type).and_return(cache_store)
      expect(cache_store).to receive(:write_if_dirty!).twice

      described_class.use(type) do |_db|
        break
      end
      described_class.use(type) do |_db|
        # do nothing
      end
    end

    it "returns the block value" do
      expect(described_class.use(type) { :return_value }).to eq(:return_value)
    end

    it "finishes writing before opening a replacement database" do
      events = Queue.new
      write_started = Queue.new
      finish_write = Queue.new
      first_cache_store = instance_double(described_class, "first_cache_store")
      second_cache_store = instance_double(described_class, "second_cache_store", write_if_dirty!: nil)
      allow(first_cache_store).to receive(:write_if_dirty!) do
        events << :write_started
        write_started << true
        finish_write.pop
        events << :write_finished
      end
      allow(described_class).to receive(:new).with(type).and_return(first_cache_store, second_cache_store)

      first_use = Thread.new { described_class.use(type) { nil } }
      write_started.pop
      second_use = Thread.new do
        events << :second_use_started
        described_class.use(type) { events << :second_database_opened }
      end
      Thread.pass while second_use.status == "run"
      finish_write << true
      [first_use, second_use].each(&:value)

      expect(Array.new(4) { events.pop }).to eq([
        :write_started,
        :second_use_started,
        :write_finished,
        :second_database_opened,
      ])
    end

    it "does not raise when used concurrently, including `break`" do
      threads = Array.new(8) do |i|
        Thread.new do
          25.times do |n|
            described_class.use(:concurrent_test) do |db|
              break if n.odd?

              db.delete("missing-#{i}-#{n}")
            end
          end
        end
      end

      expect { threads.each(&:value) }.not_to raise_error
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
        expect { sample_db.write_if_dirty! }.not_to raise_error
      end
    end

    context "without an open database" do
      before do
        sample_db.db = nil
      end

      it "does not raise an error when `close` is called on the database" do
        expect { sample_db.write_if_dirty! }.not_to raise_error
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
