# frozen_string_literal: true

require "rubocops/rubocop-cask"
RSpec.describe RuboCop::Cop::Cask::UninstallMethodsOrder, :config do
  context "with uninstall blocks" do
    context "when methods are incorrectly ordered" do
      it "detects and corrects ordering offenses in the uninstall block when each method contains a single item" do
        expect_offense(<<~CASK)
          cask 'foo' do
            uninstall quit:      "com.example.foo",
                      ^^^^ `quit` method out of order
                      launchctl: "com.example.foo"
                      ^^^^^^^^^ `launchctl` method out of order
          end
        CASK

        expect_correction(<<~CASK)
          cask 'foo' do
            uninstall launchctl: "com.example.foo",
                      quit:      "com.example.foo"
          end
        CASK
      end

      it "detects and corrects ordering offenses in the uninstall block when methods contain arrays" do
        expect_offense(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

          uninstall delete:  [
                    ^^^^^^ `delete` method out of order
                      "/usr/local/bin/foo",
                      "/usr/local/bin/foobar",
                    ],
                    script:  {
                    ^^^^^^ `script` method out of order
                      executable: "/usr/local/bin/foo",
                      sudo:       false,
                    },
                    pkgutil: "org.foo.bar"
                    ^^^^^^^ `pkgutil` method out of order
          end
        CASK

        expect_correction(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

          uninstall script:  {
                      executable: "/usr/local/bin/foo",
                      sudo:       false,
                    },
                    pkgutil: "org.foo.bar",
                    delete:  [
                      "/usr/local/bin/foo",
                      "/usr/local/bin/foobar",
                    ]
          end
        CASK
      end
    end

    context "when methods are correctly ordered" do
      it "does not report an offense" do
        expect_no_offenses(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            uninstall script:  {
                        executable: "/usr/local/bin/foo",
                        sudo:       false,
                      },
                      pkgutil: "org.foo.bar",
                      delete:  [
                        "/usr/local/bin/foo",
                        "/usr/local/bin/foobar",
                      ]
          end
        CASK
      end
    end

    context "with a single method" do
      it "does not report an offense when a single item is present in the method" do
        expect_no_offenses(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            uninstall delete: "/usr/local/bin/foo"
          end
        CASK
      end

      it "does not report an offense when the method contains an array" do
        expect_no_offenses(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            uninstall pkgutil: [
              "org.foo.bar",
              "org.foobar.bar",
            ]
          end
        CASK
      end
    end
  end

  context "with zap blocks" do
    context "when methods are incorrectly ordered" do
      it "detects and corrects ordering offenses in the zap block when each method contains a single item" do
        expect_offense(<<~CASK)
          cask 'foo' do
            zap rmdir: "/Library/Foo",
                ^^^^^ `rmdir` method out of order
                trash: "com.example.foo"
                ^^^^^ `trash` method out of order
          end
        CASK

        expect_correction(<<~CASK)
          cask 'foo' do
            zap trash: "com.example.foo",
                rmdir: "/Library/Foo"
          end
        CASK
      end

      it "detects and corrects ordering offenses in the zap block when methods contain arrays" do
        expect_offense(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            zap delete: [
                  "~/Library/Application Support/Foo",
                  "~/Library/Application Support/Bar",
                ],
                rmdir: "~/Library/Application Support",
                ^^^^^ `rmdir` method out of order
                trash: "~/Library/Application Support/FooBar"
                ^^^^^ `trash` method out of order
          end
        CASK

        expect_correction(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            zap delete: [
                  "~/Library/Application Support/Foo",
                  "~/Library/Application Support/Bar",
                ],
                trash: "~/Library/Application Support/FooBar",
                rmdir: "~/Library/Application Support"
          end
        CASK
      end
    end

    context "when methods are correctly ordered" do
      it "does not report an offense" do
        expect_no_offenses(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            zap delete: [
                  "~/Library/Application Support/Bar",
                  "~/Library/Application Support/Foo",
                ],
                trash:  "~/Library/Application Support/FooBar",
                rmdir:  "~/Library/Application Support"
          end
        CASK
      end
    end

    context "with a single method" do
      it "does not report an offense when a single item is present in the method" do
        expect_no_offenses(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            zap trash:  "~/Library/Application Support/FooBar"
          end
        CASK
      end

      it "does not report an offense when the method contains an array" do
        expect_no_offenses(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            zap trash: [
              "~/Library/Application Support/FooBar",
              "~/Library/Application Support/FooBarBar",
            ]
          end
        CASK
      end
    end
  end

  context "with both uninstall and zap blocks" do
    context "when both uninstall and zap methods are incorrectly ordered" do
      it "detects offenses and auto-corrects to the correct order" do
        expect_offense(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            uninstall delete:  [
                      ^^^^^^ `delete` method out of order
                        "/usr/local/bin/foo",
                        "/usr/local/bin/foobar",
                      ],
                      script:  {
                      ^^^^^^ `script` method out of order
                        executable: "/usr/local/bin/foo",
                        sudo:       false,
                      },
                      pkgutil: "org.foo.bar"
                      ^^^^^^^ `pkgutil` method out of order

            zap delete: [
                  "~/Library/Application Support/Bar",
                  "~/Library/Application Support/Foo",
                ],
                rmdir:  "~/Library/Application Support",
                ^^^^^ `rmdir` method out of order
                trash:  "~/Library/Application Support/FooBar"
                ^^^^^ `trash` method out of order
          end
        CASK

        expect_correction(<<~CASK)
          cask "foo" do
            url "https://example.com/foo.zip"

            uninstall script:  {
                        executable: "/usr/local/bin/foo",
                        sudo:       false,
                      },
                      pkgutil: "org.foo.bar",
                      delete:  [
                        "/usr/local/bin/foo",
                        "/usr/local/bin/foobar",
                      ]

            zap delete: [
                  "~/Library/Application Support/Bar",
                  "~/Library/Application Support/Foo",
                ],
                trash:  "~/Library/Application Support/FooBar",
                rmdir:  "~/Library/Application Support"
          end
        CASK
      end
    end

    context "when uninstall and zap methods are correctly ordered" do
      it "does not report an offense" do
        expect_no_offenses(<<~CASK)
          cask 'foo' do
            uninstall early_script: {
                        executable: "foo.sh",
                        args:       ["--unattended"],
                      },
                      launchctl:    "com.example.foo",
                      quit:         "com.example.foo",
                      signal:       ["TERM", "com.example.foo"],
                      login_item:   "FooApp",
                      kext:         "com.example.foo",
                      script:       {
                        executable: "foo.sh",
                        args:       ["--unattended"],
                      },
                      pkgutil:      "com.example.foo",
                      delete:       "~/Library/Preferences/com.example.foo",
                      trash:        "~/Library/Preferences/com.example.foo",
                      rmdir:        "~/Library/Foo"

            zap early_script: {
                  executable: "foo.sh",
                  args:       ["--unattended"],
                },
                launchctl:    "com.example.foo",
                quit:         "com.example.foo",
                signal:       ["TERM", "com.example.foo"],
                login_item:   "FooApp",
                kext:         "com.example.foo",
                script:       {
                  executable: "foo.sh",
                  args:       ["--unattended"],
                },
                pkgutil:      "com.example.foo",
                delete:       "~/Library/Preferences/com.example.foo",
                trash:        "~/Library/Preferences/com.example.foo",
                rmdir:        "~/Library/Foo"
          end
        CASK
      end
    end
  end

  context "when in-line comments are present" do
    it "keeps associated comments when auto-correcting" do
      expect_offense <<~CASK
        cask 'foo' do
          uninstall quit:      "com.example.foo", # comment on same line
                    ^^^^ `quit` method out of order
                    launchctl: "com.example.foo"
                    ^^^^^^^^^ `launchctl` method out of order
        end
      CASK

      expect_correction <<~CASK
        cask 'foo' do
          uninstall launchctl: "com.example.foo",
                    quit:      "com.example.foo" # comment on same line
        end
      CASK
    end
  end

  context "when methods are inside an `on_os` block" do
    it "detects and corrects offenses within OS-specific blocks" do
      expect_offense <<~CASK
        cask "foo" do
          on_catalina do
            uninstall trash:     "com.example.foo",
                      ^^^^^ `trash` method out of order
                      launchctl: "com.example.foo"
                      ^^^^^^^^^ `launchctl` method out of order
          end
          on_ventura do
            uninstall quit:      "com.example.foo",
                      ^^^^ `quit` method out of order
                      launchctl: "com.example.foo"
                      ^^^^^^^^^ `launchctl` method out of order
          end
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          on_catalina do
            uninstall launchctl: "com.example.foo",
                      trash:     "com.example.foo"
          end
          on_ventura do
            uninstall launchctl: "com.example.foo",
                      quit:      "com.example.foo"
          end
        end
      CASK
    end
  end
end
