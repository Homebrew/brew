# frozen_string_literal: true

require "rubocops/rubocop-cask"

describe RuboCop::Cop::Cask::OnSystemConditionals, :config do
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
            ^^^^^^^^ Don't use `on_intel` in `postflight do`, use `if Hardware::CPU.intel?` instead.
              foobar
            end
          end
        end
      CASK

      # FIXME: Infinite loop alternating between `if Hardware::CPU.intel?` and `on_intel do`.
      expect_correction <<~CASK, loop: false
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
            ^^^^^^^^^^^ Don't use `on_monterey` in `postflight do`, use `if MacOS.version == :monterey` instead.
              foobar
            end
          end
        end
      CASK

      # FIXME: Infinite loop alternating between `if MacOS.version == :monterey` and `on_monterey do`.
      expect_correction <<~CASK, loop: false
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
            ^^^^^^^^^^^^^^^^^^^^^ Don't use `on_monterey :or_older` in `postflight do`, use `if MacOS.version <= :monterey` instead.
              foobar
            end
          end
        end
      CASK

      # FIXME: Infinite loop alternating between `if MacOS.version <= :monterey` and `on_monterey :or_older do`.
      expect_correction <<~CASK, loop: false
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
          ^^^^^^^^^ Use `sha256 arm: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b", intel: "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"` instead of nesting the `sha256` stanzas in `on_intel` and `on_arm` blocks
            sha256 "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b"
          end
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
        #{"  "}
          sha256 arm: "8c62a2b791cf5f0da6066a0a4b6e85f62949cd60975da062df44adf887f4370b", intel: "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
        end
      CASK
    end

    it "accepts when there is also a `version` stanza inside the `on_arch` blocks" do
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

  context "when auditing loose `Hardware::CPU` method calls" do
    it "reports an offense when `Hardware::CPU.arm?` is used" do
      expect_offense <<~CASK
        cask 'foo' do
          if Hardware::CPU.arm? && other_condition
             ^^^^^^^^^^^^^^^^^^ Don't use `Hardware::CPU.arm?`, use `on_arm` and `on_intel` blocks instead.
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
             ^^^^^^^^^^^^^^^^^^^^ Don't use `Hardware::CPU.intel?`, use `on_arm` and `on_intel` blocks instead.
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
                                                    ^^^^^^^^^^^^^^^^^^ Don't use `Hardware::CPU.arch`, use `on_arm` and `on_intel` blocks instead.
        end
      CASK
    end
  end

  context "when auditing loose `MacOS.version` method calls" do
    it "reports an offense when `MacOS.version ==` is used" do
      expect_offense <<~CASK
        cask 'foo' do
          if MacOS.version == :catalina
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Don't use `if MacOS.version == :catalina`, use `on_catalina do` instead.
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
          if MacOS.version <= :catalina
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Don't use `if MacOS.version <= :catalina`, use `on_catalina :or_older do` instead.
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
          if MacOS.version >= :catalina
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Don't use `if MacOS.version >= :catalina`, use `on_catalina :or_newer do` instead.
            version "1.0.0"
          else
            version "2.0.0"
          end
        end
      CASK
    end
  end
end
