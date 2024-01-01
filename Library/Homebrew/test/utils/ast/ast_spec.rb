# frozen_string_literal: true

require "utils/ast"

describe Utils::AST do
  describe ".stanza_text" do
    let(:compound_license) do
      <<~RUBY.chomp
        license all_of: [
          :public_domain,
          "MIT",
          "GPL-3.0-or-later" => { with: "Autoconf-exception-3.0" },
        ]
      RUBY
    end

    it "accepts existing stanza text" do
      expect(described_class.stanza_text(:revision, "revision 1")).to eq("revision 1")
      expect(described_class.stanza_text(:license, "license :public_domain")).to eq("license :public_domain")
      expect(described_class.stanza_text(:license, 'license "MIT"')).to eq('license "MIT"')
      expect(described_class.stanza_text(:license, compound_license)).to eq(compound_license)
    end

    it "accepts a number as the stanza value" do
      expect(described_class.stanza_text(:revision, 1)).to eq("revision 1")
    end

    it "accepts a symbol as the stanza value" do
      expect(described_class.stanza_text(:license, :public_domain)).to eq("license :public_domain")
    end

    it "accepts a string as the stanza value" do
      expect(described_class.stanza_text(:license, "MIT")).to eq('license "MIT"')
    end

    it "adds indent to stanza text if specified" do
      expect(described_class.stanza_text(:revision, "revision 1", indent: 2)).to eq("  revision 1")
      expect(described_class.stanza_text(:license, 'license "MIT"', indent: 2)).to eq('  license "MIT"')
      expect(described_class.stanza_text(:license, compound_license, indent: 2)).to eq(compound_license.indent(2))
    end

    it "does not add indent if already indented" do
      expect(described_class.stanza_text(:revision, "  revision 1", indent: 2)).to eq("  revision 1")
      expect(
        described_class.stanza_text(:license, compound_license.indent(2), indent: 2),
      ).to eq(compound_license.indent(2))
    end
  end
end
