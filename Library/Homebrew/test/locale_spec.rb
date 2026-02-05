# frozen_string_literal: true

require "locale"

RSpec.describe Locale do
  describe "::parse" do
    it "parses a string in the correct format" do
      expect(described_class.parse("zh")).to eql(described_class.new("zh", nil, nil))
      expect(described_class.parse("zh-CN")).to eql(described_class.new("zh", nil, "CN"))
      expect(described_class.parse("zh-Hans")).to eql(described_class.new("zh", "Hans", nil))
      expect(described_class.parse("zh-Hans-CN")).to eql(described_class.new("zh", "Hans", "CN"))
    end

    it "correctly parses a string with a UN M.49 region code" do
      expect(described_class.parse("es-419")).to eql(described_class.new("es", nil, "419"))
    end

    describe "raises a ParserError when given" do
      it "an empty string" do
        expect { described_class.parse("") }.to raise_error(Locale::ParserError)
      end

      it "a string in a wrong format" do
        expect { described_class.parse("zh-CN-Hans") }.to raise_error(Locale::ParserError)
        expect { described_class.parse("zh_CN_Hans") }.to raise_error(Locale::ParserError)
        expect { described_class.parse("zhCNHans") }.to raise_error(Locale::ParserError)
        expect { described_class.parse("zh-CN_Hans") }.to raise_error(Locale::ParserError)
        expect { described_class.parse("zhCN") }.to raise_error(Locale::ParserError)
        expect { described_class.parse("zh_Hans") }.to raise_error(Locale::ParserError)
        expect { described_class.parse("zh-") }.to raise_error(Locale::ParserError)
        expect { described_class.parse("ZH-CN") }.to raise_error(Locale::ParserError)
        expect { described_class.parse("zh-cn") }.to raise_error(Locale::ParserError)
      end
    end
  end

  describe "::new" do
    it "raises an ArgumentError when all arguments are nil" do
      expect { described_class.new(nil, nil, nil) }.to raise_error(ArgumentError)
    end

    it "raises a ParserError when one of the arguments does not match the locale format" do
      expect { described_class.new("ZH", nil, nil) }.to raise_error(Locale::ParserError)
      expect { described_class.new(nil, "hans", nil) }.to raise_error(Locale::ParserError)
      expect { described_class.new(nil, nil, "cn") }.to raise_error(Locale::ParserError)
    end
  end

  describe "#include?" do
    subject { described_class.new("zh", "Hans", "CN") }

    specify(:aggregate_failures) do
      expect(subject).to include("zh") # rubocop:todo RSpec/NamedSubject
      expect(subject).to include("zh-CN") # rubocop:todo RSpec/NamedSubject
      expect(subject).to include("CN") # rubocop:todo RSpec/NamedSubject
      expect(subject).to include("Hans-CN") # rubocop:todo RSpec/NamedSubject
      expect(subject).to include("Hans") # rubocop:todo RSpec/NamedSubject
      expect(subject).to include("zh-Hans-CN") # rubocop:todo RSpec/NamedSubject
    end
  end

  describe "#eql?" do
    subject(:locale) { described_class.new("zh", "Hans", "CN") }

    context "when all parts match" do
      specify(:aggregate_failures) do
        expect(subject).to eql("zh-Hans-CN") # rubocop:todo RSpec/NamedSubject
        expect(subject).to eql(locale) # rubocop:todo RSpec/NamedSubject
      end
    end

    context "when only some parts match" do
      specify(:aggregate_failures) do
        expect(subject).not_to eql("zh") # rubocop:todo RSpec/NamedSubject
        expect(subject).not_to eql("zh-CN") # rubocop:todo RSpec/NamedSubject
        expect(subject).not_to eql("CN") # rubocop:todo RSpec/NamedSubject
        expect(subject).not_to eql("Hans-CN") # rubocop:todo RSpec/NamedSubject
        expect(subject).not_to eql("Hans") # rubocop:todo RSpec/NamedSubject
      end
    end

    it "does not raise if 'other' cannot be parsed" do
      expect { locale.eql?("zh_CN_Hans") }.not_to raise_error
      expect(locale.eql?("zh_CN_Hans")).to be false
    end
  end

  describe "#detect" do
    let(:locale_groups) { [["zh"], ["zh-TW"]] }

    it "finds best matching language code, independent of order" do
      expect(described_class.new("zh", nil, "TW").detect(locale_groups)).to eql(["zh-TW"])
      expect(described_class.new("zh", nil, "TW").detect(locale_groups.reverse)).to eql(["zh-TW"])
      expect(described_class.new("zh", "Hans", "CN").detect(locale_groups)).to eql(["zh"])
    end
  end
end
