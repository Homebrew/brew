# typed: true
# frozen_string_literal: true

require "utils/ast"

RSpec.describe Utils::AST::CaskAST do
  subject(:cask_ast) do
    described_class.new <<~RUBY
      cask "foo" do
        version "1.0"
        sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

        url "https://brew.sh/foo-\#{version}.dmg"
        name "Foo"

        on_arm do
          version "1.1"
          sha256 :no_check
        end
      end
    RUBY
  end

  describe ".valid_bump?" do
    let(:original) do
      <<~RUBY
        cask "foo" do
          version "1.0,10"
          sha256 arm:   "#{"a" * 64}",
                 intel: "#{"b" * 64}"

          url "https://brew.sh/foo-\#{version.csv.first}.dmg"
          name "Foo"

          depends_on macos: :ventura

          app "Foo.app"
        end
      RUBY
    end

    let(:updated) { original.sub("1.0,10", "1.0.1,2").sub("a" * 64, "c" * 64).sub("b" * 64, "d" * 64) }

    it "accepts release data and rejects changes to the download or artifacts" do
      changes = [updated, updated.sub("brew.sh", "example.org"), updated.sub("Foo.app", "Bar.app")]
      expect(changes.map { |source| described_class.valid_bump?(original, source, version: "1.0.1,2") })
        .to eq([true, false, false])
    end

    it "requires the proposed version to be a strict increase over the checkout" do
      results = %w[0.9,20 1.0,10 1.0.1,2].map do |version|
        described_class.valid_bump?(original, updated.sub("1.0.1,2", version), version:)
      end
      expect([*results, described_class.valid_bump?(original, updated, version: "1.0.2")])
        .to eq([false, false, true, false])
    end

    it "rejects malformed versions and checksums" do
      changes = { updated.sub("1.0.1,2", "1.0.1/2") => "1.0.1/2", updated.sub("c" * 64, "c" * 63) => "1.0.1,2" }
      expect(changes.map { |source, version| described_class.valid_bump?(original, source, version:) })
        .to eq([false, false])
    end

    it "accepts a bump of one architecture's version and checksum" do
      checkout = <<~RUBY
        cask "foo" do
          on_arm do
            version "1.0"
            sha256 "#{"a" * 64}"
          end
          on_intel do
            version "1.0"
            sha256 "#{"b" * 64}"
          end

          url "https://brew.sh/foo-\#{version}.dmg"
        end
      RUBY
      expect(described_class.valid_bump?(checkout, checkout.sub("1.0", "1.1").sub("a" * 64, "c" * 64),
                                         version: "1.1")).to be(true)
    end

    it "accepts only the minimum macOS version edits made by `brew audit --fix`" do
      without = ->(source) { source.sub("  depends_on macos: :ventura\n\n", "") }
      changes = [[original, updated.sub(":ventura", ":sonoma")], [without.call(original), updated],
                 [original, without.call(updated)]]
      expect(changes.map { |checkout, source| described_class.valid_bump?(checkout, source, version: "1.0.1,2") })
        .to eq([true, true, false])
    end
  end

  describe "#replace_first_stanza_value" do
    it "replaces the first matching stanza argument" do
      cask_ast.replace_first_stanza_value(:url, "https://brew.sh/foo-2.0.dmg")

      expect(cask_ast.process).to include('url "https://brew.sh/foo-2.0.dmg"')
    end
  end

  describe "#replace_stanza_value" do
    it "replaces matching stanza arguments" do
      cask_ast.replace_stanza_value(:version, "1.0", "2.0")
      cask_ast.replace_stanza_value(:sha256, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
      cask_ast.replace_stanza_value(:sha256, :no_check,
                                    "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")

      expect(cask_ast.process).to eq <<~RUBY
        cask "foo" do
          version "2.0"
          sha256 "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

          url "https://brew.sh/foo-\#{version}.dmg"
          name "Foo"

          on_arm do
            version "1.1"
            sha256 "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
          end
        end
      RUBY
    end

    it "replaces matching hash argument values" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          version "1.0"
          sha256 arm:   "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                 intel: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
          url "https://brew.sh/foo.dmg"
        end
      RUBY

      expect(
        cask_ast.replace_stanza_value(:sha256, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                      "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
      ).to eq(1)
      expect(cask_ast.process).to eq <<~RUBY
        cask "foo" do
          version "1.0"
          sha256 arm:   "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                 intel: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
          url "https://brew.sh/foo.dmg"
        end
      RUBY
    end

    it "replaces matching stanza arguments only inside on_arm blocks" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          on_arm do
            version "1.0"
          end
          on_intel do
            version "1.0"
          end
        end
      RUBY

      expect(cask_ast.replace_stanza_value(:version, "1.0", "2.0", within: :on_arm)).to eq(1)
      expect(cask_ast.process).to eq <<~RUBY
        cask "foo" do
          on_arm do
            version "2.0"
          end
          on_intel do
            version "1.0"
          end
        end
      RUBY
    end

    it "replaces matching stanza arguments only inside on_intel blocks" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          on_arm do
            version "1.0"
          end
          on_intel do
            version "1.0"
          end
        end
      RUBY

      expect(cask_ast.replace_stanza_value(:version, "1.0", "2.0", within: :on_intel)).to eq(1)
      expect(cask_ast.process).to eq <<~RUBY
        cask "foo" do
          on_arm do
            version "1.0"
          end
          on_intel do
            version "2.0"
          end
        end
      RUBY
    end

    it "keeps replacing all matching stanza arguments without a scope" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          on_arm do
            version "1.0"
          end
          on_intel do
            version "1.0"
          end
        end
      RUBY

      expect(cask_ast.replace_stanza_value(:version, "1.0", "2.0")).to eq(2)
      expect(cask_ast.process).to eq <<~RUBY
        cask "foo" do
          on_arm do
            version "2.0"
          end
          on_intel do
            version "2.0"
          end
        end
      RUBY
    end

    it "replaces matching stanza values within an on-system block" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          on_arm do
            version "1.0"
            sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
          end

          on_intel do
            version "1.0"
            sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
          end

          url "https://brew.sh/foo.dmg"
        end
      RUBY

      expect(cask_ast.replace_stanza_value(:version, "1.0", "2.0", within: :on_arm)).to eq(1)
      expect(
        cask_ast.replace_stanza_value(:sha256, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                                      within: :on_arm),
      ).to eq(1)
      expect(cask_ast.process).to eq <<~RUBY
        cask "foo" do
          on_arm do
            version "2.0"
            sha256 "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
          end

          on_intel do
            version "1.0"
            sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
          end

          url "https://brew.sh/foo.dmg"
        end
      RUBY
    end
  end

  describe "#update_depends_on_macos_minimum!" do
    def cask_with(stanzas)
      described_class.new <<~RUBY
        cask "foo" do
          version "1.0"
          sha256 :no_check

          url "https://brew.sh/foo.dmg"
          name "Foo"
          homepage "https://brew.sh/"
        #{stanzas}
          app "Foo.app"
        end
      RUBY
    end

    it "sets the minimum version of an existing stanza" do
      cask_ast = cask_with("  depends_on macos: :ventura\n")
      cask_ast.update_depends_on_macos_minimum!(:sequoia)

      expect(cask_ast.process).to include("depends_on macos: :sequoia")
    end

    it "replaces the deprecated string comparison format" do
      cask_ast = cask_with("  depends_on macos: \">= :ventura\"\n")
      cask_ast.update_depends_on_macos_minimum!(:sequoia)

      expect(cask_ast.process).to include("depends_on macos: :sequoia")
    end

    it "gives a bare macOS dependency a minimum version" do
      cask_ast = cask_with("  depends_on :macos\n")
      cask_ast.update_depends_on_macos_minimum!(:sequoia)

      expect(cask_ast.process).to include("depends_on macos: :sequoia")
    end

    it "adds a stanza when the cask has no macOS dependency" do
      cask_ast = cask_with("")
      cask_ast.update_depends_on_macos_minimum!(:sequoia)

      expect(cask_ast.process).to include(<<~RUBY)
        homepage "https://brew.sh/"

          depends_on macos: :sequoia

          app "Foo.app"
      RUBY
    end

    it "keeps a new stanza grouped with an existing `depends_on`" do
      cask_ast = cask_with("  depends_on arch: :arm64\n")
      cask_ast.update_depends_on_macos_minimum!(:sequoia)

      expect(cask_ast.process).to include(<<~RUBY)
        depends_on arch: :arm64
          depends_on macos: :sequoia
      RUBY
    end

    it "inserts a minimum beside a maximum_macos requirement" do
      cask_ast = cask_with("  depends_on maximum_macos: :sequoia\n")
      cask_ast.update_depends_on_macos_minimum!(:ventura)

      expect(cask_ast.process).to include("depends_on maximum_macos: :sequoia\n  depends_on macos: :ventura")
    end

    it "returns false when the stanza states a maximum version" do
      cask_ast = cask_with("  depends_on macos: \"<= :ventura\"\n")

      expect(cask_ast.update_depends_on_macos_minimum!(:sequoia)).to be(false)
    end

    it "returns false when the stanza lists exact versions" do
      cask_ast = cask_with("  depends_on macos: [:ventura, :sonoma]\n")

      expect(cask_ast.update_depends_on_macos_minimum!(:sequoia)).to be(false)
    end

    it "returns false when the dependency is nested in an `on_system` block" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          url "https://brew.sh/foo.dmg"

          on_arm do
            depends_on macos: :ventura
          end

          app "Foo.app"
        end
      RUBY

      expect(cask_ast.update_depends_on_macos_minimum!(:sequoia)).to be(false)
    end

    it "returns false without a stanza to insert before" do
      expect(cask_ast.update_depends_on_macos_minimum!(:sequoia)).to be(false)
    end
  end

  describe "#depends_on_macos?" do
    it "detects casks with a macOS dependency" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          version "1.0"
          sha256 :no_check
          url "https://brew.sh/foo.dmg"
          depends_on macos: ">= :ventura"
        end
      RUBY

      expect(cask_ast.depends_on_macos?).to be(true)
    end

    it "does not treat a scoped maximum as a macOS dependency for the audit prefilter" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          on_macos do
            depends_on maximum_macos: :sequoia
          end
        end
      RUBY

      expect(cask_ast.depends_on_macos?).to be(false)
    end

    it "returns false without a macOS dependency" do
      expect(cask_ast.depends_on_macos?).to be(false)
    end
  end
end
