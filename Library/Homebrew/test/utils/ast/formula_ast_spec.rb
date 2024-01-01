# frozen_string_literal: true

require "utils/ast"

describe Utils::AST::FormulaAST do
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

  describe "#remove_stanza" do
    context "when stanza to be removed is a single line followed by a blank line" do
      subject(:formula_ast) do
        described_class.new <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            license :cannot_represent

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
            end

            head do
              url "https://brew.sh/foo.git"
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
      <<~RUBY.chomp.indent(2)
        bottle do
          sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
            head "https://brew.sh/foo.git"
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"
            head "https://brew.sh/foo.git"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
            end
          end
        RUBY
      end

      let(:new_contents) do
        <<~RUBY.chomp
          class Foo < Formula
            url "https://brew.sh/foo-1.0.tar.gz"

            bottle do
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
            end

            head do
              url "https://brew.sh/foo.git"
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
              sha256 "f7b1fc772c79c20fddf621ccc791090bc1085fcef4da6cca03399424c66e06ca" => :sierra
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
