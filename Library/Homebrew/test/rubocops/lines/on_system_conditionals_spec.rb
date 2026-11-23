# typed: strict
# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::OnSystemConditionals do
  sig { returns(RuboCop::Cop::FormulaAudit::OnSystemConditionals) }
  subject(:cop) { described_class.new }

  context "when auditing OS conditionals" do
    it "reports an offense when `OS.linux?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if OS.linux?
          ^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if OS.linux?`, use `on_linux do`.
            url 'https://brew.sh/linux-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_linux do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        on_macos do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `OS.mac?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if OS.mac?
          ^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if OS.mac?`, use `on_macos do`.
            url 'https://brew.sh/mac-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_macos do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        on_linux do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `unless OS.mac?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_linux do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `unless OS.mac?` with an `else` branch is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            url 'https://brew.sh/linux-1.0.tgz'
          else
            url 'https://brew.sh/mac-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_linux do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        on_macos do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        end
      RUBY
    end

    it "skips correction when unless has an empty body" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
          else
            url "https://brew.sh/mac.tgz"
          end
        end
      RUBY

      expect_no_corrections
    end

    it "skips correction when unless assigns a local used by a sibling block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            linux_url = "https://brew.sh/linux.tgz"
          end
          on_linux do
            url linux_url
          end
        end
      RUBY

      expect_no_corrections
    end

    shared_examples "an outer local reference" do |assignment, usage|
      it "preserves the outer local in `#{usage}`" do
        expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
          class Foo < Formula
            unless OS.mac?
            ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
              #{assignment}
            end
            #{usage}
          end
        RUBY

        expect_no_corrections
      end
    end

    include_examples "an outer local reference", 'urls = ["linux.tgz"]', "urls.each { |urls| url urls }"
    include_examples "an outer local reference", 'urls = ["linux.tgz"]', "consume(urls) { |urls| url urls }"
    include_examples "an outer local reference", "target = Class.new", "def target.helper; end"
    include_examples "an outer local reference", "target = Class.new", "class Child < target; end"
    include_examples "an outer local reference", "target = Class.new", "class << target; end"
    include_examples "an outer local reference", "target = Class.new", "binding.local_variable_get(:target)"

    it "preserves a local observed through an earlier binding" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          context = binding
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            target = Class.new
          end
          context.local_variable_get(:target)
        end
      RUBY

      expect_no_corrections
    end

    shared_examples "a loop that retains its locals" do |loop_header|
      it "preserves a cached value across iterations of `#{loop_header}`" do
        expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
          class Foo < Formula
            #{loop_header}
              unless OS.mac?
              ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
                path ||= compute_path
                url path
              end
              advance
            end
          end
        RUBY

        expect_no_corrections
      end
    end

    include_examples "a loop that retains its locals", "while more?"
    include_examples "a loop that retains its locals", "until finished?"
    include_examples "a loop that retains its locals", "for item in items"

    it "preserves next targeting an enclosing loop" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          deps.each do |dep|
            next unless OS.mac?
            ^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            depends_on dep
          end
        end
      RUBY

      expect_no_corrections
    end

    it "preserves the enclosing iterator's numbered parameter" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          deps.each do
            depends_on _1 unless OS.mac?
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            puts "done"
          end
        end
      RUBY

      expect_no_corrections
    end

    it "preserves the enclosing iterator's implicit it parameter" do
      allow(self).to receive(:ruby_version).and_return(4.0)

      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          deps.each do
            depends_on it unless OS.mac?
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            puts 'done'
          end
        end
      RUBY

      expect_no_corrections
    end

    it "preserves a pattern binding referenced after the branch" do
      allow(self).to receive(:ruby_version).and_return(4.0)

      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            metadata => { url: download_url }
          end
          url download_url
        end
      RUBY

      expect_no_corrections
    end

    it "preserves retry targeting an enclosing rescue" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          begin
            fetch_metadata
          rescue
            retry unless OS.mac?
            ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            fallback
          end
        end
      RUBY

      expect_no_corrections
    end

    it "preserves a named capture referenced after the branch" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            /(?<release>[0-9]+)/ =~ version.to_s
          end
          url release
        end
      RUBY

      expect_no_corrections
    end

    it "preserves a local read by a later compound assignment" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            suffix = "linux"
          end
          url(suffix ||= "default")
        end
      RUBY

      expect_no_corrections
    end

    it "leaves an assigned conditional intact" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          source_url = unless OS.mac?
                       ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            "linux.tgz"
          else
            "mac.tgz"
          end
        end
      RUBY

      expect_no_corrections
    end

    it "keeps leading branch comments" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          unless OS.mac?
          ^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
            # Linux download
            url "linux.tgz"
          else
            # macOS download
            url "mac.tgz"
          end
        end
      RUBY

      expect_no_corrections
    end

    it "corrects an assignment and its use in the same branch despite an unrelated method local" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          if OS.mac?
          ^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if OS.mac?`, use `on_macos do`.
            mac_url = "https://brew.sh/mac.tgz"
            url mac_url
          end
          def install
            mac_url = "other"
            puts mac_url
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          on_macos do
        mac_url = "https://brew.sh/mac.tgz"
            url mac_url
        end
          def install
            mac_url = "other"
            puts mac_url
          end
        end
      RUBY
    end

    it "reports an offense when a modifier `unless OS.mac?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          depends_on "patchelf" unless OS.mac?
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.mac?`, use `on_linux do`.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_linux do
        depends_on "patchelf"
        end
        end
      RUBY
    end

    it "reports an offense when `unless OS.linux?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          unless OS.linux?
          ^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.linux?`, use `on_macos do`.
            url 'https://brew.sh/mac-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_macos do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `unless OS.linux?` with an `else` branch is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          unless OS.linux?
          ^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `unless OS.linux?`, use `on_macos do`.
            url 'https://brew.sh/mac-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_macos do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        on_linux do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `on_macos` is used in fetch method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def fetch
            on_macos do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_macos` in `def fetch`, use `if OS.mac?`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def fetch
            if OS.mac?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_macos` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_macos do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_macos` in `def install`, use `if OS.mac?`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if OS.mac?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_linux` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_linux do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_linux` in `def install`, use `if OS.linux?`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if OS.linux?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_macos` is used in test block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            on_macos do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_macos` in `test do`, use `if OS.mac?`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            if OS.mac?
              true
            end
          end
        end
      RUBY
    end
  end

  context "when auditing Hardware::CPU conditionals" do
    it "reports an offense when `Hardware::CPU.arm?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if Hardware::CPU.arm?
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if Hardware::CPU.arm?`, use `on_arm do`.
            url 'https://brew.sh/linux-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_arm do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        on_intel do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `Hardware::CPU.intel?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if Hardware::CPU.intel?
          ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if Hardware::CPU.intel?`, use `on_intel do`.
            url 'https://brew.sh/mac-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_intel do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        on_arm do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports the CPU arch call in an unless condition" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          unless Hardware::CPU.arch
                 ^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `Hardware::CPU.arch`, use `on_arm` and `on_intel` blocks.
            url "foo.tgz"
          end
        end
      RUBY
    end

    it "reports an offense when `unless Hardware::CPU.arm?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          unless Hardware::CPU.arm?
          ^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Avoid a negated CPU check for architecture-specific formula declarations.
            url 'https://brew.sh/intel-1.0.tgz'
          end
        end
      RUBY

      expect_no_corrections
    end

    it "reports an offense when `unless Hardware::CPU.intel?` with an `else` branch is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          unless Hardware::CPU.intel?
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Avoid a negated CPU check for architecture-specific formula declarations.
            url 'https://brew.sh/arm-1.0.tgz'
          else
            url 'https://brew.sh/intel-1.0.tgz'
          end
        end
      RUBY

      expect_no_corrections
    end

    it "reports an offense when `on_intel` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_intel do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_intel` in `def install`, use `if Hardware::CPU.intel?`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if Hardware::CPU.intel?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_arm` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_arm do
            ^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_arm` in `def install`, use `if Hardware::CPU.arm?`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if Hardware::CPU.arm?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_intel` is used in test block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            on_intel do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_intel` in `test do`, use `if Hardware::CPU.intel?`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            if Hardware::CPU.intel?
              true
            end
          end
        end
      RUBY
    end
  end

  context "when auditing MacOS.version conditionals" do
    it "reports an offense when `MacOS.version ==` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version == :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if MacOS.version == :monterey`, use `on_monterey do`.
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_monterey do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense without a correction when `unless MacOS.version ==` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          unless MacOS.version == :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Avoid the negated macOS version check `unless MacOS.version == :monterey`.
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_no_corrections
    end

    it "reports an offense when `MacOS.version <=` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version <= :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if MacOS.version <= :monterey`, use `on_system :linux, macos: :monterey_or_older do`.
            url 'https://brew.sh/mac-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_system :linux, macos: :monterey_or_older do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `MacOS.version <` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version < :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if MacOS.version < :monterey`, use `on_system do`.
            url 'https://brew.sh/mac-1.0.tgz'
          end
        end
      RUBY
    end

    it "reports an offense when `MacOS.version >=` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version >= :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if MacOS.version >= :monterey`, use `on_monterey :or_newer do`.
            url 'https://brew.sh/mac-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY
    end

    it "reports an offense when `MacOS.version >` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version > :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of `if MacOS.version > :monterey`, use `on_monterey do`.
            url 'https://brew.sh/mac-1.0.tgz'
          end
        end
      RUBY
    end

    it "reports an offense when `on_monterey` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_monterey do
            ^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_monterey` in `def install`, use `if MacOS.version == :monterey`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if MacOS.version == :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_monterey :or_older` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_monterey :or_older do
            ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_monterey :or_older` in `def install`, use `if MacOS.version <= :monterey`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if MacOS.version <= :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_monterey :or_newer` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_monterey :or_newer do
            ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_monterey :or_newer` in `def install`, use `if MacOS.version >= :monterey`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if MacOS.version >= :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_system :linux, macos: :monterey_or_newer` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_system :linux, macos: :monterey_or_newer do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_system :linux, macos: :monterey_or_newer` in `def install`, use `if OS.linux? || MacOS.version >= :monterey`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if OS.linux? || MacOS.version >= :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_monterey` is used in test block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            on_monterey do
            ^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_monterey` in `test do`, use `if MacOS.version == :monterey`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            if MacOS.version == :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_system :linux, macos: :monterey` is used in test block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            on_system :linux, macos: :monterey do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Instead of using `on_system :linux, macos: :monterey` in `test do`, use `if OS.linux? || MacOS.version == :monterey`.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            if OS.linux? || MacOS.version == :monterey
              true
            end
          end
        end
      RUBY
    end
  end
end
