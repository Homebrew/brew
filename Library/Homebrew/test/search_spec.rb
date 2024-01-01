# frozen_string_literal: true

require "search"

describe Homebrew::Search do
  describe "#query_regexp" do
    it "correctly parses a regex query" do
      expect(described_class.query_regexp("/^query$/")).to eq(/^query$/)
    end

    it "returns the original string if it is not a regex query" do
      expect(described_class.query_regexp("query")).to eq("query")
    end

    it "raises an error if the query is an invalid regex" do
      expect { described_class.query_regexp("/+/") }.to raise_error(/not a valid regex/)
    end
  end

  describe "#search" do
    let(:collection) { ["with-dashes"] }

    context "when given a block" do
      let(:collection) { [["with-dashes", "withdashes"]] }

      it "searches by the selected argument" do
        expect(described_class.search(collection, /withdashes/) { |_, short_name| short_name }).not_to be_empty
        expect(described_class.search(collection, /withdashes/) { |long_name, _| long_name }).to be_empty
      end
    end

    context "when given a regex" do
      it "does not simplify strings" do
        expect(described_class.search(collection, /with-dashes/)).to eq ["with-dashes"]
      end
    end

    context "when given a string" do
      it "simplifies both the query and searched strings" do
        expect(described_class.search(collection, "with dashes")).to eq ["with-dashes"]
      end
    end

    context "when searching a Hash" do
      let(:collection) { { "foo" => "bar" } }

      it "returns a Hash" do
        expect(described_class.search(collection, "foo")).to eq "foo" => "bar"
      end

      context "with a nil value" do
        let(:collection) { { "foo" => nil } }

        it "does not raise an error" do
          expect(described_class.search(collection, "foo")).to eq "foo" => nil
        end
      end
    end
  end
end
