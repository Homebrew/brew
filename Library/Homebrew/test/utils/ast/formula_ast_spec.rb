# typed: true
# frozen_string_literal: true

require "utils/ast"

RSpec.describe Utils::AST::FormulaAST do
  subject(:formula_ast) do
    described_class.new <<~RUBY
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tar.gz"
        license all_of: [
          :public_domain,
          "MIT",
          "GPL-3.0-or-later" => { with: "Autoconf-exception-3.0" },
        ]
      end
    RUBY
  end

  describe "#resource" do
    it "finds resource block in a formula" do
      formula_ast = described_class.new <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"

          resource "foo" do
            url "https://brew.sh/foo-1.0.tar.gz"
          end
        end
      RUBY

      expect(formula_ast.resource("foo").children[2].children[2].value).to eq("https://brew.sh/foo-1.0.tar.gz")
    end

    it "finds resource in `stable` block" do
      formula_ast = described_class.new <<~RUBY
        class Foo < Formula
          stable do
            url "https://brew.sh/foo-1.0.tar.gz"

            resource "foo" do
              url "https://brew.sh/foo-1.1.tar.gz"
            end
          end

          resource "foo" do
            url "https://brew.sh/foo-1.0.tar.gz"
          end
        end
      RUBY

      expect(formula_ast.resource("foo").children[2].children[2].value).to eq("https://brew.sh/foo-1.1.tar.gz")
    end

    it "raises an exception when resource block does not exist" do
      formula_ast = described_class.new <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"
        end
      RUBY

      expect { formula_ast.resource("foo") }.to raise_error("Could not find resource 'foo' block!")
    end
  end

  describe "#replace_stanza" do
    it "replaces the specified stanza in a formula" do
      formula_ast.replace_stanza(:license, :public_domain)
      expect(formula_ast.process).to eq <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"
          license :public_domain
        end
      RUBY
    end
  end

  describe "#add_stanza" do
    it "adds the specified stanza to a formula" do
      formula_ast.add_stanza(:revision, 1)
      expect(formula_ast.process).to eq <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"
          license all_of: [
            :public_domain,
            "MIT",
            "GPL-3.0-or-later" => { with: "Autoconf-exception-3.0" },
          ]
          revision 1
        end
      RUBY
    end
  end

  describe "#replace_stable_stanza_value" do
    it "replaces a stable stanza argument" do
      formula_ast.replace_stable_stanza_value(:url, "https://brew.sh/foo-2.0.tar.gz")

      expect(formula_ast.process).to eq <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-2.0.tar.gz"
          license all_of: [
            :public_domain,
            "MIT",
            "GPL-3.0-or-later" => { with: "Autoconf-exception-3.0" },
          ]
        end
      RUBY
    end
  end

  describe "#replace_stable_stanza_hash_value" do
    subject(:formula_ast) do
      described_class.new <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo.git",
              tag:      "v1.0",
              revision: "abc123"
        end
      RUBY
    end

    it "replaces a stable stanza keyword value" do
      formula_ast.replace_stable_stanza_hash_value(:url, :tag, "v2.0")
      formula_ast.replace_stable_stanza_hash_value(:url, :revision, "def456")

      expect(formula_ast.process).to eq <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo.git",
              tag:      "v2.0",
              revision: "def456"
        end
      RUBY
    end
  end

  describe "#add_stanzas_after" do
    it "adds multiple stanzas after the specified stanza" do
      formula_ast.add_stanzas_after(:url, [[:mirror, "https://example.com/foo-1.0.tar.gz"], [:version, "1.0"]])

      expect(formula_ast.process).to eq <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"
          mirror "https://example.com/foo-1.0.tar.gz"
          version "1.0"
          license all_of: [
            :public_domain,
            "MIT",
            "GPL-3.0-or-later" => { with: "Autoconf-exception-3.0" },
          ]
        end
      RUBY
    end

    it "adds stanzas after comments following a multi-line stanza" do
      formula_ast = described_class.new <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo.git",
              tag:      "v1.0",
              revision: "abc"
          # keep with url
          license :mit
        end
      RUBY

      formula_ast.add_stanzas_after(:url, [[:version, "1.0"]])

      expect(formula_ast.process).to eq <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo.git",
              tag:      "v1.0",
              revision: "abc"
          # keep with url
          version "1.0"
          license :mit
        end
      RUBY
    end
  end

  describe "#replace_resource_stanza_value" do
    subject(:formula_ast) do
      described_class.new <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"

          resource "bar" do
            url "https://brew.sh/bar-1.0.tar.gz"
            mirror "https://example.com/bar-1.0.tar.gz"
            sha256 "#{"e" * 64}"
          end
        end
      RUBY
    end

    it "replaces resource stanza arguments" do
      formula_ast.replace_resource_stanza_value("bar", :url, "https://brew.sh/bar-2.0.tar.gz")
      formula_ast.replace_resource_stanza_value("bar", :mirror, "https://example.com/bar-2.0.tar.gz")
      formula_ast.replace_resource_stanza_value("bar", :sha256, "f" * 64)
      formula_ast.add_stanzas_after(:sha256, [[:version, "2.0"]], parent: formula_ast.resource("bar"))

      expect(formula_ast.process).to eq <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"

          resource "bar" do
            url "https://brew.sh/bar-2.0.tar.gz"
            mirror "https://example.com/bar-2.0.tar.gz"
            sha256 "#{"f" * 64}"
            version "2.0"
          end
        end
      RUBY
    end
  end

  describe "#replace_resource_stanzas" do
    it "inserts resource stanzas before the install method" do
      formula_ast = described_class.new <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"

          def install
            bin.install "foo"
          end
        end
      RUBY

      formula_ast.replace_resource_stanzas <<~RUBY
        resource "bar" do
          url "https://brew.sh/bar-1.0.tar.gz"
          sha256 "#{"e" * 64}"
        end

      RUBY

      expect(formula_ast.process).to eq <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"

          resource "bar" do
            url "https://brew.sh/bar-1.0.tar.gz"
            sha256 "#{"e" * 64}"
          end

          def install
            bin.install "foo"
          end
        end
      RUBY
    end

    context "when resource stanzas already exist" do
      subject(:formula_ast) do
        described_class.new <<~RUBY
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            # RESOURCE-ERROR: Unable to resolve "baz"
            resource "bar" do
              url "https://brew.sh/bar-1.0.tar.gz"
              sha256 "#{"e" * 64}"
            end

            def install
              bin.install "foo"
            end
          end
        RUBY
      end

      it "replaces the existing resource stanza group" do
        formula_ast.replace_resource_stanzas <<~RUBY
          resource "baz" do
            url "https://brew.sh/baz-1.0.tar.gz"
            sha256 "#{"f" * 64}"
          end

        RUBY

        expect(formula_ast.process).to eq <<~RUBY
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            resource "baz" do
              url "https://brew.sh/baz-1.0.tar.gz"
              sha256 "#{"f" * 64}"
            end

            def install
              bin.install "foo"
            end
          end
        RUBY
      end
    end

    context "when resource stanzas are split into multiple groups" do
      subject(:formula_ast) do
        described_class.new <<~RUBY
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            resource "bar" do
              url "https://brew.sh/bar-1.0.tar.gz"
              sha256 "#{"e" * 64}"
            end

            depends_on "pkg-config" => :build

            resource "baz" do
              url "https://brew.sh/baz-1.0.tar.gz"
              sha256 "#{"f" * 64}"
            end
          end
        RUBY
      end

      it "returns :multiple_groups" do
        expect(formula_ast.replace_resource_stanzas("")).to be(:multiple_groups)
      end
    end
  end

  describe "#remove_stanza" do
    context "when stanza to be removed is a single line followed by a blank line" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license :cannot_represent

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "removes the line containing the stanza" do
        formula_ast.remove_stanza(:license)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when stanza to be removed is a multiline block followed by a blank line" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license all_of: [
              :public_domain,
              "MIT",
              "GPL-3.0-or-later" => { with: "Autoconf-exception-3.0" },
            ]

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "removes the lines containing the stanza" do
        formula_ast.remove_stanza(:license)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when stanza to be removed has a comment on the same line" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license :cannot_represent # comment

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
             # comment

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "removes the stanza but keeps the comment and its whitespace" do
        formula_ast.remove_stanza(:license)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when stanza to be removed has a comment on the next line" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license :cannot_represent
            # comment

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            # comment

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "removes the stanza but keeps the comment" do
        formula_ast.remove_stanza(:license)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when stanza to be removed has newlines before and after" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end

            head do
              url "https://brew.sh/foo.git"
              branch "develop"
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            head do
              url "https://brew.sh/foo.git"
              branch "develop"
            end
          end
        RUBY
      end

      it "removes the stanza and preceding newline" do
        formula_ast.remove_stanza(:bottle)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when stanza to be removed is at the end of the formula" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license :cannot_represent

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license :cannot_represent
          end
        RUBY
      end

      it "removes the stanza and preceding newline" do
        formula_ast.remove_stanza(:bottle)
        expect(formula_ast.process).to eq(new_contents)
      end
    end
  end

  describe "#add_bottle_block" do
    let(:bottle_output) do
      <<-RUBY
  bottle do
    sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
  end
      RUBY
    end

    context "when `license` is a string" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license "MIT"
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license "MIT"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "adds `bottle` after `license`" do
        formula_ast.add_bottle_block(bottle_output)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when `license` is a symbol" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license :cannot_represent
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license :cannot_represent

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "adds `bottle` after `license`" do
        formula_ast.add_bottle_block(bottle_output)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when `license` is multiline" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license all_of: [
              :public_domain,
              "MIT",
              "GPL-3.0-or-later" => { with: "Autoconf-exception-3.0" },
            ]
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license all_of: [
              :public_domain,
              "MIT",
              "GPL-3.0-or-later" => { with: "Autoconf-exception-3.0" },
            ]

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "adds `bottle` after `license`" do
        formula_ast.add_bottle_block(bottle_output)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when `head` is a string" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            head "https://brew.sh/foo.git", branch: "develop"
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            head "https://brew.sh/foo.git", branch: "develop"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "adds `bottle` after `head`" do
        formula_ast.add_bottle_block(bottle_output)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when `head` is a block" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            head do
              url "https://brew.sh/foo.git"
              branch "develop"
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end

            head do
              url "https://brew.sh/foo.git"
              branch "develop"
            end
          end
        RUBY
      end

      it "adds `bottle` before `head`" do
        formula_ast.add_bottle_block(bottle_output)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when there is a comment on the same line" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz" # comment
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz" # comment

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "adds `bottle` after the comment" do
        formula_ast.add_bottle_block(bottle_output)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when the next line is a comment" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            # comment
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            # comment

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end
          end
        RUBY
      end

      it "adds `bottle` after the comment" do
        formula_ast.add_bottle_block(bottle_output)
        expect(formula_ast.process).to eq(new_contents)
      end
    end

    context "when the next line is blank and the one after it is a comment" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            # comment
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sonoma
            end

            # comment
          end
        RUBY
      end

      it "adds `bottle` before the comment" do
        formula_ast.add_bottle_block(bottle_output)
        expect(formula_ast.process).to eq(new_contents)
      end
    end
  end
end
