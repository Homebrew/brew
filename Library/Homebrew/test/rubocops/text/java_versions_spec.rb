# typed: true
# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::JavaVersions do
  subject(:cop) { described_class.new }

  context "when auditing Java versions" do
    it "reports no offenses for non-core formulae" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "openjdk@25"

          def install
            java_version = "17"
            Language::Java.java_home("21")
            Language::Java.java_home_env(java_version)
            Language::Java.overridable_java_home_env
            bin.write_jar_script libexec/"test.jar", "test"
          end
        end
      RUBY
    end

    it "reports no offenses when there is no OpenJDK dependency" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          def install
            java_version = "17"
            Language::Java.java_home("21")
            Language::Java.java_home_env(java_version)
            Language::Java.overridable_java_home_env
            bin.write_jar_script libexec/"test.jar", "test"
          end
        end
      RUBY
    end

    it "reports no offenses when there are multiple OpenJDK dependencies" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          depends_on "openjdk@21" => :build
          depends_on "openjdk@25"

          def install
            java_version = "25"
            Language::Java.java_home("21")
            Language::Java.java_home_env(java_version)
            Language::Java.overridable_java_home_env("21")
            bin.write_jar_script libexec/"test.jar", "test", java_version: "25"
          end
        end
      RUBY
    end

    it "reports no offenses when Java version arguments match versioned OpenJDK dependency" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          depends_on "openjdk@25"

          def install
            java_version = "25"
            Language::Java.java_home("25")
            Language::Java.java_home_env(java_version)
            Language::Java.overridable_java_home_env "25"
            bin.write_jar_script libexec/"test.jar", "test", java_version: "25"
          end
        end
      RUBY
    end

    it "reports no offenses when Java version arguments match unversioned OpenJDK dependency" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          depends_on "openjdk"

          def install
            java_version = nil
            Language::Java.java_home
            Language::Java.java_home_env(java_version)
            Language::Java.overridable_java_home_env
            bin.write_jar_script libexec/"test.jar", "test"
          end
        end
      RUBY
    end

    it "reports and corrects mismatched java_home version arguments for versioned OpenJDK dependency" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          depends_on "openjdk@25"

          def install
            java_version = "21"
                           ^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)
            openjdk_version = nil
                              ^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)

            Language::Java.java_home(java_version)
            Language::Java.java_home openjdk_version
            Language::Java.java_home("17")
                                     ^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)
            Language::Java.java_home_env nil
                                         ^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)
            Language::Java.overridable_java_home_env
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "openjdk@25"

          def install
            java_version = "25"
            openjdk_version = "25"

            Language::Java.java_home(java_version)
            Language::Java.java_home openjdk_version
            Language::Java.java_home("25")
            Language::Java.java_home_env("25")
            Language::Java.overridable_java_home_env("25")
          end
        end
      RUBY
    end

    it "reports and corrects mismatched java_home version arguments for unversioned OpenJDK dependency" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          depends_on "openjdk"

          def install
            java_version = "21"
                           ^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk`)
            openjdk_version = nil

            Language::Java.java_home(java_version)
            Language::Java.java_home openjdk_version
            Language::Java.java_home("17")
                                     ^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk`)
            Language::Java.java_home_env(nil)
                                         ^^^ FormulaAudit/JavaVersions: Argument is unnecessary when using unversioned OpenJDK
            Language::Java.overridable_java_home_env "21"
                                                     ^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk`)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "openjdk"

          def install
            java_version = nil
            openjdk_version = nil

            Language::Java.java_home(java_version)
            Language::Java.java_home openjdk_version
            Language::Java.java_home
            Language::Java.java_home_env
            Language::Java.overridable_java_home_env
          end
        end
      RUBY
    end

    it "reports and corrects mismatched write_jar_script version arguments for versioned OpenJDK dependency" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          depends_on "openjdk@25"

          def install
            java_version = "21" # intentionally unused so expected to remain unmodified
            openjdk_version = nil
                              ^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)

            bin.write_jar_script libexec/"test.jar", "test-1"
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)
            bin.write_jar_script libexec/"test.jar", "test-2", java_version: "21"
                                                                             ^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)
            bin.write_jar_script(libexec/"test.jar", "test-3", java_version: nil)
                                                                             ^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk@25`)
            bin.write_jar_script(libexec/"test.jar", "test-4", java_version: openjdk_version)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "openjdk@25"

          def install
            java_version = "21" # intentionally unused so expected to remain unmodified
            openjdk_version = "25"

            bin.write_jar_script libexec/"test.jar", "test-1", java_version: "25"
            bin.write_jar_script libexec/"test.jar", "test-2", java_version: "25"
            bin.write_jar_script(libexec/"test.jar", "test-3", java_version: "25")
            bin.write_jar_script(libexec/"test.jar", "test-4", java_version: openjdk_version)
          end
        end
      RUBY
    end

    it "reports and corrects mismatched write_jar_script version arguments for unversioned OpenJDK dependency" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          depends_on "openjdk"

          def install
            java_version = "21" # intentionally unused so expected to remain unmodified
            openjdk_version = "21"
                              ^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk`)

            bin.write_jar_script libexec/"test.jar", "test-1"
            bin.write_jar_script libexec/"test.jar", "test-2", java_version: "25"
                                                                             ^^^^ FormulaAudit/JavaVersions: Java version argument should match the specified dependency (`openjdk`)
            bin.write_jar_script(libexec/"test.jar", "test-3", java_version: openjdk_version)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "openjdk"

          def install
            java_version = "21" # intentionally unused so expected to remain unmodified
            openjdk_version = nil

            bin.write_jar_script libexec/"test.jar", "test-1"
            bin.write_jar_script libexec/"test.jar", "test-2"
            bin.write_jar_script(libexec/"test.jar", "test-3", java_version: openjdk_version)
          end
        end
      RUBY
    end
  end
end
