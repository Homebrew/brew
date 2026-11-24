# typed: true
# frozen_string_literal: true

require "rubocops/single_use_method"
require "rubydex"

RSpec.describe RuboCop::Cop::Homebrew::SingleUseMethod do
  subject(:cop) { described_class.new(RuboCop::Config.new(other_cops)) }

  let(:other_cops) { {} }

  context "with a formula" do
    it "reports a method only called once" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
          end

          def make_args
          ^^^^^^^^^^^^^ Inline `make_args` into its only caller.
            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "reports a method in a file with invalid bytes in an interpolated string" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args, "\\xFF\#{prefix}"
          end

          def make_args
          ^^^^^^^^^^^^^ Inline `make_args` into its only caller.
            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "does not report a hook method that Homebrew also calls" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make"
            post_install
          end

          def post_install
            (var/"foo").mkpath
          end
        end
      RUBY
    end

    it "does not report a fetch hook method that Homebrew also calls" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            fetch
            system "make"
          end

          def fetch
            system "curl", "-O", "https://example.com/foo.tar.gz"
          end
        end
      RUBY
    end

    it "does not report a method called more than once" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
            system "make", "install", *make_args
          end

          def make_args
            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "does not report a method that is never called" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make"
          end
        end
      RUBY
    end

    it "does not report a method also referenced by a symbol" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
            odebug method(:make_args)
          end

          def make_args
            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "does not report a method also named in a string" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
            system "make", *public_send("make_args")
          end

          def make_args
            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "does not report a method that may be called through an interpolated name" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
            system "make", *public_send(:"make_\#{target}")
          end

          def make_args
            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "does not report a method called on another receiver" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *Formula["bar"].make_args
          end

          def make_args
            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "reports a method called on self" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *self.make_args
          end

          def make_args
          ^^^^^^^^^^^^^ Inline `make_args` into its only caller.
            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "does not report a method that returns early" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
          end

          def make_args
            return [] if build.head?

            ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "does not report a method that yields" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            in_build_directory { system "make" }
          end

          def in_build_directory
            cd("build") { yield }
          end
        end
      RUBY
    end

    it "does not report a method with an on_system block" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
          end

          def make_args
            arch = "aarch64"
            on_intel do
              arch = "x86_64"
            end
            ["ARCH=\#{arch}"]
          end
        end
      RUBY
    end

    it "does not report a method with an on_system block using a numbered parameter" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
          end

          def make_args
            args = ["PREFIX=\#{prefix}"]
            on_intel { args << "ARCH=\#{_1}" }
            args
          end
        end
      RUBY
    end

    it "does not report a memoised method" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
          end

          def make_args
            @make_args ||= ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    it "does not report a method taking a block" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            in_build_directory { system "make" }
          end

          def in_build_directory(&block)
            cd("build", &block)
          end
        end
      RUBY
    end

    it "does not report a method checking for a block" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
          end

          def make_args
            block_given? ? ["--verbose"] : []
          end
        end
      RUBY
    end

    it "does not report a method with a rescue called in a condition" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make" if new_version?
          end

          def new_version?
            version.major >= 2
          rescue ArgumentError
            false
          end
        end
      RUBY
    end

    it "does not report a method with a rescue called in an `||` operand" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            build_version = tagged_version || version.to_s
            system "make", "VERSION=\#{build_version}"
          end

          def tagged_version
            (buildpath/"VERSION").read
          rescue Errno::ENOENT
            nil
          end
        end
      RUBY
    end

    it "does not report a method with a rescue called in a `case`/`in` subject" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            case build_type
            in "release" then system "make"
            end
          end

          def build_type
            (buildpath/"TYPE").read
          rescue Errno::ENOENT
            "release"
          end
        end
      RUBY
    end

    it "does not report a method whose rescue variable its caller already uses" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            begin
              system "make"
            rescue => e
              odie e
            end
            write_config
          end

          def write_config
            (etc/"foo").write "bar"
          rescue => e
            opoo e
          end
        end
      RUBY
    end

    it "reports a method with a rescue called as a statement" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "make"
            write_config
          end

          def write_config
          ^^^^^^^^^^^^^^^^ Inline `write_config` into its only caller.
            (etc/"foo").write "bar"
          rescue => e
            opoo e
          end
        end
      RUBY
    end

    it "does not report a method that calls super" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "make", *make_args
          end

          def make_args
            super + ["PREFIX=\#{prefix}"]
          end
        end
      RUBY
    end

    context "with a Metrics/MethodLength limit" do
      let(:other_cops) { { "Metrics/MethodLength" => { "Enabled" => true, "Max" => 3 } } }

      it "does not report a method that would make its caller too long" do
        expect_no_offenses(<<~RUBY)
          class Foo < Formula
            def install
              system "make", *make_args
              system "make", "install"
            end

            def make_args
              args = ["PREFIX=\#{prefix}"]
              args << "--with-foo"
            end
          end
        RUBY
      end
    end

    context "with a Metrics/AbcSize limit" do
      let(:other_cops) { { "Metrics/AbcSize" => { "Enabled" => true, "Max" => 3 } } }

      it "does not report a method that would make its caller too complex" do
        expect_no_offenses(<<~RUBY)
          class Foo < Formula
            def install
              system "make", *make_args
            end

            def make_args
              ["PREFIX=\#{prefix}", "--with-foo=\#{Formula["foo"].opt_prefix}"]
            end
          end
        RUBY
      end
    end

    context "with a Metrics/CyclomaticComplexity limit" do
      let(:other_cops) { { "Metrics/CyclomaticComplexity" => { "Enabled" => true, "Max" => 2 } } }

      it "does not report a method that would make its caller too complex" do
        expect_no_offenses(<<~RUBY)
          class Foo < Formula
            def install
              system "make", "clean" if build.head?
              system "make", *make_args
            end

            def make_args
              ["PREFIX=\#{prefix}", ("--with-foo" if build.with?("foo"))].compact
            end
          end
        RUBY
      end
    end

    context "with a Metrics/PerceivedComplexity limit" do
      let(:other_cops) { { "Metrics/PerceivedComplexity" => { "Enabled" => true, "Max" => 2 } } }

      it "does not report a method that would make its caller too complex" do
        expect_no_offenses(<<~RUBY)
          class Foo < Formula
            def install
              system "make", *make_args
            end

            def make_args
              if build.head?
                ["--head"]
              else
                ["PREFIX=\#{prefix}"]
              end
            end
          end
        RUBY
      end
    end

    context "with a Metrics/BlockNesting limit" do
      let(:other_cops) { { "Metrics/BlockNesting" => { "Enabled" => true, "Max" => 2 } } }

      it "does not report a method that would nest its caller too deeply" do
        expect_no_offenses(<<~RUBY)
          class Foo < Formula
            def install
              if build.head?
                system "make", *make_args
              end
            end

            def make_args
              if build.with?("foo")
                if build.with?("bar")
                  ["--with-foo-bar"]
                end
              end
            end
          end
        RUBY
      end
    end

    context "with a Metrics/BlockNesting limit counting modifier forms" do
      let(:other_cops) do
        { "Metrics/BlockNesting" => { "Enabled" => true, "Max" => 1, "CountModifierForms" => true } }
      end

      it "does not report a method that would nest its caller too deeply" do
        expect_no_offenses(<<~RUBY)
          class Foo < Formula
            def install
              system "make", *make_args if build.head?
            end

            def make_args
              ["--with-foo"] if build.with?("foo")
            end
          end
        RUBY
      end
    end

    context "with a Metrics/BlockLength limit" do
      let(:other_cops) { { "Metrics/BlockLength" => { "Enabled" => true, "Max" => 2 } } }

      it "does not report a method that would make its calling block too long" do
        expect_no_offenses(<<~RUBY)
          class Foo < Formula
            def test_args
              args = ["--version"]
              args << "--verbose"
            end

            test do
              system bin/"foo", *test_args
            end
          end
        RUBY
      end
    end

    context "with a Metrics/BlockLength limit that allows the calling block" do
      let(:other_cops) do
        { "Metrics/BlockLength" => { "Enabled" => true, "Max" => 2, "AllowedMethods" => ["test"] } }
      end

      it "reports a method only called once" do
        expect_offense(<<~RUBY)
          class Foo < Formula
            def test_args
            ^^^^^^^^^^^^^ Inline `test_args` into its only caller.
              args = ["--version"]
              args << "--verbose"
            end

            test do
              system bin/"foo", *test_args
            end
          end
        RUBY
      end
    end

    it "does not report a recursive method" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            visit(prefix)
          end

          def visit(path)
            path.children.each { |child| visit(child) }
          end
        end
      RUBY
    end
  end

  context "without a formula" do
    let(:source) do
      <<~RUBY
        class Foo
          def run
            puts message
          end

          private

          def message
            "Hello"
          end
        end
      RUBY
    end

    def index(*sources)
      directory = mktmpdir
      paths = sources.each_with_index.map do |source, number|
        path = directory/"file #{number}.rb"
        path.write(source)
        path.to_s
      end
      graph = Rubydex::Graph.new
      graph.index_all(paths)
      graph.resolve
    end

    it "does not report anything without a project index" do
      expect_no_offenses(source)
    end

    it "reports a private method only called once in the project index" do
      cop.project_index = index(source)

      expect_offense(<<~RUBY)
        class Foo
          def run
            puts message
          end

          private

          def message
          ^^^^^^^^^^^ Inline `message` into its only caller.
            "Hello"
          end
        end
      RUBY
    end

    it "reports a private method when the project index holds a copy of the same file" do
      cop.project_index = index(source, source)

      expect_offense(<<~RUBY)
        class Foo
          def run
            puts message
          end

          private

          def message
          ^^^^^^^^^^^ Inline `message` into its only caller.
            "Hello"
          end
        end
      RUBY
    end

    it "reports a private method when the project index holds a symlink to the same file" do
      directory = mktmpdir
      (directory/"real").mkpath
      (directory/"real/foo.rb").write(source)
      (directory/"link").make_symlink(directory/"real")
      graph = Rubydex::Graph.new
      graph.index_all([(directory/"real/foo.rb").to_s, (directory/"link/foo.rb").to_s])
      cop.project_index = graph.resolve

      expect_offense(<<~RUBY)
        class Foo
          def run
            puts message
          end

          private

          def message
          ^^^^^^^^^^^ Inline `message` into its only caller.
            "Hello"
          end
        end
      RUBY
    end

    it "does not report a private method called from another file when the project index holds a copy" do
      cop.project_index = index(source, source, <<~RUBY)
        class Bar
          def run
            message
          end
        end
      RUBY

      expect_no_offenses(source)
    end

    it "does not report a private method called from an indexed file that was deleted" do
      directory = mktmpdir
      (directory/"foo.rb").write(source)
      (directory/"caller.rb").write(<<~RUBY)
        class Bar
          def run
            message
          end
        end
      RUBY
      graph = Rubydex::Graph.new
      graph.index_all([(directory/"foo.rb").to_s, (directory/"caller.rb").to_s])
      (directory/"caller.rb").delete
      cop.project_index = graph.resolve

      expect_no_offenses(source)
    end

    it "does not report a private method called from another file" do
      cop.project_index = index(source, <<~RUBY)
        class Bar
          def run
            message
          end
        end
      RUBY

      expect_no_offenses(source)
    end

    it "does not report a private method referenced by a symbol in another file" do
      cop.project_index = index(source, <<~RUBY)
        RSpec.describe Foo do
          it "says hello" do
            allow(subject).to receive(:message).and_return("Hi")
          end
        end
      RUBY

      expect_no_offenses(source)
    end

    it "does not report a private method stubbed by a hash key in another file" do
      cop.project_index = index(source, <<~RUBY)
        RSpec.describe Foo do
          it "says hello" do
            allow(subject).to receive_messages(message: "Hi")
          end
        end
      RUBY

      expect_no_offenses(source)
    end

    it "does not report a private method defined in another class" do
      cop.project_index = index(source, <<~RUBY)
        class Bar
          private

          def message
            "Goodbye"
          end
        end
      RUBY

      expect_no_offenses(source)
    end

    it "does not report a public method" do
      public_source = source.sub("  private\n\n", "")
      cop.project_index = index(public_source)

      expect_no_offenses(public_source)
    end
  end
end
