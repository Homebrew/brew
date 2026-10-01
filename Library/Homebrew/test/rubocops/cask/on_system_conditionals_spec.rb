# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::OnSystemConditionals, :config do
  context "when auditing nested `on_*` blocks" do
    it "reports an offense when identical `on_*` blocks are nested" do
      expect_offense <<~CASK
        cask 'foo' do
          on_big_sur :or_older do
            on_big_sur :or_older do
            ^^^^^^^^^^^^^^^^^^^^ Remove the redundant nested `on_big_sur :or_older` block.
              version "1.0"
            end
          end
        end
      CASK

      expect_no_corrections
    end

    it "reports an offense when identical architecture blocks are nested" do
      expect_offense <<~CASK
        cask 'foo' do
          on_arm do
            on_arm do
            ^^^^^^ Remove the redundant nested `on_arm` block.
              version "1.0"
            end
          end
        end
      CASK
    end

    it "reports an offense when identical `on_system` blocks are nested" do
      expect_offense <<~CASK
        cask 'foo' do
          on_system :linux, macos: :big_sur_or_older do
            on_system :linux, macos: :big_sur_or_older do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Remove the redundant nested `on_system :linux, macos: :big_sur_or_older` block.
              version "1.0"
            end
          end
        end
      CASK
    end

    it "reports an offense when identical `on_*` blocks have an intervening conditional" do
      expect_offense <<~CASK
        cask 'foo' do
          on_big_sur :or_older do
            on_arm do
              on_big_sur :or_older do
              ^^^^^^^^^^^^^^^^^^^^ Remove the redundant nested `on_big_sur :or_older` block.
                version "1.0"
              end
            end
          end
        end
      CASK
    end

    it "accepts nested `on_*` blocks with different methods or arguments" do
      expect_no_offenses <<~CASK
        cask 'foo' do
          on_ventura :or_older do
            on_big_sur :or_older do
              version "1.0"
            end
          end

          on_big_sur :or_older do
            on_big_sur do
              version "2.0"
            end
          end
        end
      CASK
    end

    it "accepts nested methods with explicit receivers" do
      expect_no_offenses <<~CASK
        cask 'foo' do
          on_arm do
            helper.on_arm do
              helper.on_arm do
                version "1.0"
              end
            end
          end
        end
      CASK
    end

    it "prefers flight stanza offenses for redundant nested `on_*` blocks" do
      expect_offense <<~CASK
        cask 'foo' do
          postflight do
            on_arm do
            ^^^^^^ Instead of using `on_arm` in `postflight do`, use `if Hardware::CPU.arm?`.
              on_arm do
              ^^^^^^ Instead of using `on_arm` in `postflight do`, use `if Hardware::CPU.arm?`.
                system_command "/bin/echo"
              end
            end
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          postflight do
            if Hardware::CPU.arm?
              if Hardware::CPU.arm?
                system_command "/bin/echo"
              end
            end
          end
        end
      CASK
    end
  end

  context "when auditing `postflight` stanzas" do
    it "accepts when there are no `on_*` blocks" do
      expect_no_offenses <<~CASK
        cask 'foo' do
          postflight do
            foobar
          end
        end
      CASK
    end

    it "reports an offense it contains an `on_intel` block" do
      expect_offense <<~CASK
        cask 'foo' do
          postflight do
            on_intel do
            ^^^^^^^^ Instead of using `on_intel` in `postflight do`, use `if Hardware::CPU.intel?`.
              foobar
            end
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          postflight do
            if Hardware::CPU.intel?
              foobar
            end
          end
        end
      CASK
    end

    it "reports an offense when it contains an `on_monterey` block" do
      expect_offense <<~CASK
        cask 'foo' do
          postflight do
            on_monterey do
            ^^^^^^^^^^^ Instead of using `on_monterey` in `postflight do`, use `if MacOS.version == :monterey`.
              foobar
            end
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          postflight do
            if MacOS.version == :monterey
              foobar
            end
          end
        end
      CASK
    end

    it "reports an offense when it contains an `on_monterey :or_older` block" do
      expect_offense <<~CASK
        cask 'foo' do
          postflight do
            on_monterey :or_older do
            ^^^^^^^^^^^^^^^^^^^^^ Instead of using `on_monterey :or_older` in `postflight do`, use `if MacOS.version <= :monterey`.
              foobar
            end
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          postflight do
            if MacOS.version <= :monterey
              foobar
            end
          end
        end
      CASK
    end
  end

  context "when auditing `sha256` stanzas inside `on_arch` blocks" do
    it "accepts when there are no `on_arch` blocks" do
      expect_no_offenses <<~CASK
        cask 'foo' do
          sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
        end
      CASK
    end

    it "accepts when the `sha256` stanza is used with keyword arguments" do
      expect_no_offenses <<~CASK
        cask 'foo' do
          sha256 arm:   "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94",
                 intel: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
        end
      CASK
    end

    it "reports an offense when `sha256` has identical values for different architectures" do
      expect_offense <<~CASK
        cask 'foo' do
          sha256 arm:   "5f42cb017dd07270409eaee7c3b4a164ffa7c0f21d85c65840c4f81aab21d457",
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ sha256 values for different architectures should not be identical.
                 intel: "5f42cb017dd07270409eaee7c3b4a164ffa7c0f21d85c65840c4f81aab21d457"
        end
      CASK
    end

    it "accepts identical macOS values when Linux checksums are also present" do
      expect_no_offenses <<~CASK
        cask "foo" do
          sha256 arm:          "macos",
                 intel:        "macos",
                 x86_64_linux: "linux"
        end
      CASK
    end

    it "reports an offense when every architecture value is identical" do
      expect_offense <<~CASK
        cask "foo" do
          sha256 arm:          "same",
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ sha256 values for different architectures should not be identical.
                 intel:        "same",
                 arm64_linux:  "same",
                 x86_64_linux: "same"
        end
      CASK
    end

    it "reports identical checksums when Linux is restricted to Intel" do
      expect_offense <<~CASK
        cask "foo" do
          sha256 arm: "same",
          ^^^^^^^^^^^^^^^^^^^ sha256 values for different architectures should not be identical.
                 intel: "same",
                 x86_64_linux: "same"

          on_linux do
            depends_on arch: :x86_64
          end
        end
      CASK
    end

    it "reports identical checksums when Linux is restricted to ARM" do
      expect_offense <<~CASK
        cask "foo" do
          sha256 arm: "same",
          ^^^^^^^^^^^^^^^^^^^ sha256 values for different architectures should not be identical.
                 intel: "same",
                 arm64_linux: "same"

          on_linux do
            depends_on arch: :arm64
          end
        end
      CASK
    end

    it "reports identical checksums with a top-level architecture restriction" do
      expect_offense <<~CASK
        cask "foo" do
          sha256 arm: "same",
          ^^^^^^^^^^^^^^^^^^^ sha256 values for different architectures should not be identical.
                 intel: "same",
                 x86_64_linux: "same"

          depends_on arch: :intel
        end
      CASK
    end

    it "accepts identical checksums when an unrestricted Linux architecture is missing" do
      expect_no_offenses <<~CASK
        cask "foo" do
          sha256 arm: "same",
                 intel: "same",
                 x86_64_linux: "same"
        end
      CASK
    end

    it "does not apply a macOS architecture restriction to Linux checksums" do
      expect_no_offenses <<~CASK
        cask "foo" do
          sha256 arm: "same",
                 intel: "same",
                 x86_64_linux: "same"

          on_macos do
            depends_on arch: :x86_64
          end
        end
      CASK
    end

    it "accepts a single architecture checksum" do
      expect_no_offenses <<~CASK
        cask "foo" do
          sha256 arm: "same"

          depends_on arch: :arm64
        end
      CASK
    end

    it "accepts when there is only one `on_arch` block" do
      expect_no_offenses <<~CASK
        cask 'foo' do
          on_intel do
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
        end
      CASK
    end

    it "reports an offense when `sha256` is specified in all `on_arch` blocks" do
      expect_offense <<~CASK
        cask 'foo' do
          on_intel do
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
          on_arm do
          ^^^^^^^^^ Don't nest only the `sha256` stanzas in `on_intel` and `on_arm` blocks
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          sha256 arm: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b", intel: "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
        end
      CASK
    end

    it "reports an offense but does not autocorrect when an `on_arch` block includes comments" do
      expect_offense <<~CASK
        cask 'foo' do
          on_intel do
            # comment
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
          on_arm do
          ^^^^^^^^^ Don't nest only the `sha256` stanzas in `on_intel` and `on_arm` blocks
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK

      expect_no_corrections
    end

    it "accepts when there is also a `version` stanza inside the `on_arch` blocks with different versions" do
      expect_no_offenses <<~CASK
        cask 'foo' do
          on_intel do
            version "1.0.0"
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
          on_arm do
            version "2.0.0"
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK
    end

    it "accepts when there is also a `version` stanza inside only a single `on_arch` block" do
      expect_no_offenses <<~CASK
        cask 'foo' do
          on_intel do
            version "2.0.0"
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
          on_arm do
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK
    end
  end

  context "when auditing `sha256` stanzas inside `on_os` blocks" do
    it "moves architecture-specific checksums to the top level" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 arm:   "arm",
                   intel: "intel"

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            depends_on arch: :x86_64

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 arm:          "arm",
                 intel:        "intel",
                 x86_64_linux: "linux"

          on_macos do
            app "Foo.app"
          end
          on_linux do
            depends_on arch: :x86_64

            app_image "Foo.AppImage"
          end
        end
      CASK
    end

    it "duplicates a universal macOS checksum across macOS architectures" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "macos"

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 arm64_linux:  "arm-linux",
                   x86_64_linux: "intel-linux"

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 arm:          "macos",
                 intel:        "macos",
                 arm64_linux:  "arm-linux",
                 x86_64_linux: "intel-linux"

          on_macos do
            app "Foo.app"
          end
          on_linux do
            app_image "Foo.AppImage"
          end
        end
      CASK
    end

    it "combines every architecture dependency in an OS block" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "macos"

            depends_on arch: :x86_64
            depends_on arch: :arm64
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            depends_on arch: [:intel, :arm64]
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 arm:          "macos",
                 intel:        "macos",
                 arm64_linux:  "linux",
                 x86_64_linux: "linux"

          on_macos do
            depends_on arch: :x86_64
            depends_on arch: :arm64
          end
          on_linux do
            depends_on arch: [:intel, :arm64]
          end
        end
      CASK
    end

    it "combines top-level and OS-scoped architecture dependencies" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "macos"

            depends_on arch: :x86_64

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            app_image "Foo.AppImage"
          end

          depends_on arch: :arm64
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 arm:         "macos",
                 intel:       "macos",
                 arm64_linux: "linux"

          on_macos do
            depends_on arch: :x86_64

            app "Foo.app"
          end
          on_linux do
            app_image "Foo.AppImage"
          end

          depends_on arch: :arm64
        end
      CASK
    end

    it "handles bare Intel dependencies and the macOS x86_64 checksum alias" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 x86_64: "macos"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            depends_on arch: :intel
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 x86_64:       "macos",
                 x86_64_linux: "linux"

          on_linux do
            depends_on arch: :intel
          end
        end
      CASK
    end

    it "uses one checksum when the OS checksums are identical" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "checksum"

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "checksum"

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 "checksum"

          on_macos do
            app "Foo.app"
          end
          on_linux do
            app_image "Foo.AppImage"
          end
        end
      CASK
    end

    it "uses one `no_check` checksum when both OS blocks skip verification" do
      expect_offense <<~CASK
        cask "foo" do
          version :latest

          on_macos do
            sha256 :no_check

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 :no_check

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version :latest
          sha256 :no_check

          on_macos do
            app "Foo.app"
          end
          on_linux do
            app_image "Foo.AppImage"
          end
        end
      CASK
    end

    it "does not add a second top-level `sha256` stanza" do
      expect_no_offenses <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 "top-level"

          on_macos do
            sha256 "macos"
          end
          on_linux do
            sha256 "linux"
          end
        end
      CASK
    end

    it "removes OS blocks that contain only a checksum" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "macos"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 arm:          "macos",
                 intel:        "macos",
                 arm64_linux:  "linux",
                 x86_64_linux: "linux"
        end
      CASK
    end

    it "preserves a trailing comment on the `version` stanza" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3" # Keep this version note.

          on_macos do
            sha256 "macos"

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3" # Keep this version note.
          sha256 arm:          "macos",
                 intel:        "macos",
                 arm64_linux:  "linux",
                 x86_64_linux: "linux"

          on_macos do
            app "Foo.app"
          end
          on_linux do
            app_image "Foo.AppImage"
          end
        end
      CASK
    end

    it "reports but does not correct when the OS blocks need reordering" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"
          end
          on_macos do
            sha256 "macos"
          end
        end
      CASK

      expect_no_corrections
    end

    it "reports but does not correct when an OS block's stanzas need reordering" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            app "Foo.app"

            sha256 "macos"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_no_corrections
    end

    it "reports but does not correct when the `version` stanza needs reordering" do
      expect_offense <<~CASK
        cask "foo" do
          on_macos do
            sha256 "macos"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"
          end

          version "1.2.3"
        end
      CASK

      expect_no_corrections
    end

    it "reports but does not correct when stanza grouping must edit after a nested checksum" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "macos"
            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"
            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_no_corrections
    end

    it "preserves grouping after removing a non-leading nested checksum" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            version "1.2.3-macos"
            sha256 "macos"

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 arm:          "macos",
                 intel:        "macos",
                 arm64_linux:  "linux",
                 x86_64_linux: "linux"

          on_macos do
            version "1.2.3-macos"

            app "Foo.app"
          end
          on_linux do
            app_image "Foo.AppImage"
          end
        end
      CASK
    end

    it "accepts OS blocks with different versions" do
      expect_no_offenses <<~CASK
        cask "foo" do
          on_macos do
            version "1.2.3"
            sha256 "macos"

            app "Foo.app"
          end
          on_linux do
            version "1.2.4"
            sha256 "linux"

            app_image "Foo.AppImage"
          end
        end
      CASK
    end

    it "does not remove comments within a `sha256` stanza" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 arm: "arm", # Keep this architecture note.
                   intel: "intel"

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            depends_on arch: :x86_64

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_no_corrections
    end

    it "does not remove a trailing comment on a `sha256` stanza" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "macos" # Keep this checksum note.

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_no_corrections
    end

    it "does not detach a comment immediately above a `sha256` stanza" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            # Keep this checksum note.
            sha256 "macos"

            app "Foo.app"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"

            app_image "Foo.AppImage"
          end
        end
      CASK

      expect_no_corrections
    end

    it "does not detach a comment immediately above a removable OS block" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          # macOS ships a universal build.
          on_macos do
            sha256 "macos"
          end
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"
          end
        end
      CASK

      expect_no_corrections
    end

    it "does not remove a trailing comment on an OS block" do
      expect_offense <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "macos"
          end # macOS ships a universal build.
          on_linux do
          ^^^^^^^^^^^ Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks
            sha256 "linux"
          end
        end
      CASK

      expect_no_corrections
    end

    it "ignores repeated OS blocks" do
      expect_no_offenses <<~CASK
        cask "foo" do
          version "1.2.3"

          on_macos do
            sha256 "first"
          end
          on_macos do
            sha256 "second"
          end
          on_linux do
            sha256 "linux"
          end
        end
      CASK
    end
  end

  context "when auditing identical `version` stanzas inside `on_arch` blocks" do
    it "reports an offense when `version` is identical in both arch blocks but `sha256` differs" do
      expect_offense <<~CASK
        cask 'foo' do
          on_intel do
            version "1.0.0"
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
          on_arm do
          ^^^^^^^^^ Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks
            version "1.0.0"
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          version "1.0.0"
          sha256 arm: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b", intel: "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
        end
      CASK
    end

    it "reports an offense when both `version` and `sha256` are identical in both arch blocks" do
      expect_offense <<~CASK
        cask 'foo' do
          on_intel do
            version "1.0.0"
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
          on_arm do
          ^^^^^^^^^ Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks
            version "1.0.0"
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          version "1.0.0"
          sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
        end
      CASK
    end

    it "reports an offense but does not autocorrect when an `on_arch` block includes comments" do
      expect_offense <<~CASK
        cask 'foo' do
          on_intel do
            version "1.0.0"
            # comment
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
          on_arm do
          ^^^^^^^^^ Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks
            version "1.0.0"
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK

      expect_no_corrections
    end
  end

  context "when `on_arch` blocks are nested inside `on_os` blocks" do
    it "reports an offense when `on_arch` blocks with identical versions are inside an `on_os` block" do
      expect_offense <<~CASK
        cask 'foo' do
          on_sonoma :or_newer do
            on_intel do
              version "1.0.0"
              sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
            end
            on_arm do
            ^^^^^^^^^ Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks
              version "1.0.0"
              sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
            end
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          on_sonoma :or_newer do
            version "1.0.0"
            sha256 arm: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b", intel: "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
        end
      CASK
    end

    it "reports an offense when `on_arch` blocks with only `sha256` are inside an `on_os` block" do
      expect_offense <<~CASK
        cask 'foo' do
          on_sonoma :or_newer do
            on_intel do
              sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
            end
            on_arm do
            ^^^^^^^^^ Don't nest only the `sha256` stanzas in `on_intel` and `on_arm` blocks
              sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
            end
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          on_sonoma :or_newer do
            sha256 arm: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b", intel: "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end
        end
      CASK
    end

    it "reports offenses for every eligible `on_arch` pair across sibling `on_os` blocks" do
      expect_offense <<~CASK
        cask 'foo' do
          on_sonoma :or_newer do
            on_intel do
              version "1.0.0"
              sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
            end
            on_arm do
            ^^^^^^^^^ Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks
              version "1.0.0"
              sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
            end
          end

          on_sequoia :or_newer do
            on_intel do
              version "2.0.0"
              sha256 "d72f430f8f4e71cbce4d3648f364f95f8f422bcdd668a8d3260f39ee3f6f3cec"
            end
            on_arm do
            ^^^^^^^^^ Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks
              version "2.0.0"
              sha256 "7686f28e546238da94ce4dc89be623f7dc801f7e44e7011fdb7f3f471675f5ee"
            end
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          on_sonoma :or_newer do
            version "1.0.0"
            sha256 arm: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b", intel: "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end

          on_sequoia :or_newer do
            version "2.0.0"
            sha256 arm: "7686f28e546238da94ce4dc89be623f7dc801f7e44e7011fdb7f3f471675f5ee", intel: "d72f430f8f4e71cbce4d3648f364f95f8f422bcdd668a8d3260f39ee3f6f3cec"
          end
        end
      CASK
    end

    it "still autocorrects a matching pair when a later `on_os` block has only one arch block" do
      expect_offense <<~CASK
        cask 'foo' do
          on_sonoma :or_newer do
            on_intel do
              version "1.0.0"
              sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
            end
            on_arm do
            ^^^^^^^^^ Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks
              version "1.0.0"
              sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
            end
          end

          on_sequoia :or_newer do
            on_arm do
              version "3.0.0"
              sha256 "5f42cb017dd07270409eaee7c3b4a164ffa7c0f21d85c65840c4f81aab21d457"
            end
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          on_sonoma :or_newer do
            version "1.0.0"
            sha256 arm: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b", intel: "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          end

          on_sequoia :or_newer do
            on_arm do
              version "3.0.0"
              sha256 "5f42cb017dd07270409eaee7c3b4a164ffa7c0f21d85c65840c4f81aab21d457"
            end
          end
        end
      CASK
    end
  end

  context "when auditing loose `Hardware::CPU` method calls" do
    it "reports an offense when `Hardware::CPU.arm?` is used" do
      expect_offense <<~CASK
        cask 'foo' do
          if Hardware::CPU.arm? && other_condition
             ^^^^^^^^^^^^^^^^^^ Instead of `Hardware::CPU.arm?`, use `on_arm` and `on_intel` blocks.
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          else
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK
    end

    it "reports an offense when `Hardware::CPU.intel?` is used" do
      expect_offense <<~CASK
        cask 'foo' do
          if Hardware::CPU.intel? && other_condition
             ^^^^^^^^^^^^^^^^^^^^ Instead of `Hardware::CPU.intel?`, use `on_arm` and `on_intel` blocks.
            sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
          else
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK
    end

    it "reports an offense when `Hardware::CPU.arch` is used" do
      expect_offense <<~'CASK'
        cask 'foo' do
          version "1.2.3"
          sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"

          url "https://example.com/foo-#{version}-#{Hardware::CPU.arch}.zip"
                                                    ^^^^^^^^^^^^^^^^^^ Instead of `Hardware::CPU.arch`, use `on_arm` and `on_intel` blocks.
        end
      CASK
    end
  end

  context "when auditing loose `MacOS.version` method calls" do
    it "reports an offense when `MacOS.version ==` is used" do
      expect_offense <<~CASK
        cask 'foo' do
          if MacOS.version == :big_sur
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Instead of `if MacOS.version == :big_sur`, use `on_big_sur do`.
            version "1.0.0"
          else
            version "2.0.0"
          end
        end
      CASK
    end

    it "reports an offense when `MacOS.version <=` is used" do
      expect_offense <<~CASK
        cask 'foo' do
          if MacOS.version <= :big_sur
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Instead of `if MacOS.version <= :big_sur`, use `on_big_sur :or_older do`.
            version "1.0.0"
          else
            version "2.0.0"
          end
        end
      CASK
    end

    it "reports an offense when `MacOS.version >=` is used" do
      expect_offense <<~CASK
        cask 'foo' do
          if MacOS.version >= :big_sur
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Instead of `if MacOS.version >= :big_sur`, use `on_big_sur :or_newer do`.
            version "1.0.0"
          else
            version "2.0.0"
          end
        end
      CASK
    end
  end
end
