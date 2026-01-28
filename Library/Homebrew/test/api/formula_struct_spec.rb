# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API::FormulaStruct do
  describe "#stringify_symbol" do
      specify(:aggregate_failures) do
        expect(described_class.stringify_symbol(:example)).to eq(":example")
        expect(described_class.stringify_symbol("example")).to eq("example")
      end
  end

  describe "#deep_stringify_symbols and #deep_unstringify_symbols" do
    it "converts all symbols in nested hashes and arrays", :aggregate_failures do
      with_symbols = {
        a: :symbol_a,
        b: {
          c: :symbol_c,
          d: ["string_d", :symbol_d],
        },
        e: [:symbol_e1, { f: :symbol_f }],
        g: "string_g",
      }

      without_symbols = {
        ":a" => ":symbol_a",
        ":b" => {
          ":c" => ":symbol_c",
          ":d" => ["string_d", ":symbol_d"],
        },
        ":e" => [":symbol_e1", { ":f" => ":symbol_f" }],
        ":g" => "string_g",
      }

      expect(described_class.deep_stringify_symbols(with_symbols)).to eq(without_symbols)
      expect(described_class.deep_unstringify_symbols(without_symbols)).to eq(with_symbols)
    end
  end

  describe "#deep_compact_blank" do
    it "removes blank values from nested hashes and arrays" do
      input = {
        a: "",
        b: [],
        c: {},
        d: {
          e: "value",
          f: nil,
          g: {
            h: "",
            i: true,
            j: {
              k: nil,
              l: "",
            },
          },
          m: ["", nil],
        },
        n: [nil, "", 2, [], { o: nil }],
        p: false,
        q: 0,
        r: 0.0,
      }

      expected_output = {
        d: {
          e: "value",
          g: {
            i: true,
          },
        },
        n: [2],
      }

      expect(described_class.deep_compact_blank(input)).to eq(expected_output)
    end
  end

  describe "#extract_shared_items" do
    it "extracts shared items from multiple lists" do
      list1 = [1, 2, 3, 4]
      list2 = [3, 4, 5, 6]
      list3 = [3, 4, 5, 6, 7]

      expected_shared = [3, 4]
      expected_list1 = [1, 2]
      expected_list2 = [5, 6]
      expected_list3 = [5, 6, 7]

      shared, l1, l2, l3 = described_class.extract_shared_items(list1, list2, list3)

      expect(shared).to eq(expected_shared)
      expect(l1).to eq(expected_list1)
      expect(l2).to eq(expected_list2)
      expect(l3).to eq(expected_list3)
    end
  end
end
