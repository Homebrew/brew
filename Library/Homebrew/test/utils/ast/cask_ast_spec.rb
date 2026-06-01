# typed: true
# frozen_string_literal: true

require "utils/ast"

RSpec.describe Utils::AST::CaskAST do
  subject(:cask_ast) do
    klass.new <<~RUBY
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

  let(:klass) { Utils::AST::CaskAST }

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
      cask_ast = klass.new <<~RUBY
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
      cask_ast = klass.new <<~RUBY
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
      cask_ast = klass.new <<~RUBY
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
      cask_ast = klass.new <<~RUBY
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
      cask_ast = klass.new <<~RUBY
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

  describe "#depends_on_macos?" do
    it "detects casks with a macOS dependency" do
      cask_ast = klass.new <<~RUBY
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
