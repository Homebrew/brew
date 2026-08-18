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

  describe "#remove_stanza_hash_pair!" do
    def cask_with(url_stanza)
      described_class.new <<~RUBY
        cask "foo" do
          version "1.0"
          sha256 :no_check

        #{url_stanza}  name "Foo"
        end
      RUBY
    end

    it "removes a key written on its own line" do
      cask_ast = cask_with(%Q(  url "https://brew.sh/foo.dmg",\n      verified: "brew.sh/"\n))
      cask_ast.remove_stanza_hash_pair!(:url, :verified)

      expect(cask_ast.process).to include(%Q(  url "https://brew.sh/foo.dmg"\n  name "Foo"\n))
    end

    it "removes a key written on the same line" do
      cask_ast = cask_with(%Q(  url "https://brew.sh/foo.dmg", verified: "brew.sh/"\n))
      cask_ast.remove_stanza_hash_pair!(:url, :verified)

      expect(cask_ast.process).to include(%Q(  url "https://brew.sh/foo.dmg"\n))
    end

    it "keeps the remaining keys when removing the first of several" do
      cask_ast = cask_with(%Q(  url "https://brew.sh/foo.dmg",\n      verified: "brew.sh/",\n      using: :post\n))
      cask_ast.remove_stanza_hash_pair!(:url, :verified)

      expect(cask_ast.process).to include(%Q(  url "https://brew.sh/foo.dmg",\n      using: :post\n))
    end

    it "keeps the remaining keys when removing the last of several" do
      cask_ast = cask_with(%Q(  url "https://brew.sh/foo.dmg",\n      using: :post,\n      verified: "brew.sh/"\n))
      cask_ast.remove_stanza_hash_pair!(:url, :verified)

      expect(cask_ast.process).to include(%Q(  url "https://brew.sh/foo.dmg",\n      using: :post\n))
    end

    it "removes the key from every matching stanza" do
      cask_ast = described_class.new <<~RUBY
        cask "foo" do
          on_arm do
            url "https://brew.sh/arm.dmg", verified: "brew.sh/"
          end
          on_intel do
            url "https://brew.sh/intel.dmg", verified: "brew.sh/"
          end
        end
      RUBY
      cask_ast.remove_stanza_hash_pair!(:url, :verified)

      expect(cask_ast.process).not_to include("verified")
    end

    it "returns false when the key is absent" do
      cask_ast = cask_with(%Q(  url "https://brew.sh/foo.dmg"\n))

      expect(cask_ast.remove_stanza_hash_pair!(:url, :verified)).to be(false)
    end

    it "returns false when the hash is the stanza's only argument" do
      cask_ast = cask_with(%Q(  url "https://brew.sh/foo.dmg"\n  depends_on macos: :sequoia\n))

      expect(cask_ast.remove_stanza_hash_pair!(:depends_on, :macos)).to be(false)
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

    it "returns false without a macOS dependency" do
      expect(cask_ast.depends_on_macos?).to be(false)
    end
  end
end
