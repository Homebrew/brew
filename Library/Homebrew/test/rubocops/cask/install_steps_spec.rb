# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::InstallSteps, :config do
  it "reports an offense when a flight block and matching steps are both present" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          touch "foo"
        end

        postflight_steps do
        ^^^^^^^^^^^^^^^^^^^ `postflight` and `postflight_steps` cannot both be used.
          touch "foo"
        end
      end
    CASK
  end

  it "reports an offense when a steps block contains Ruby code" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight_steps do
          system "true"
          ^^^^^^^^^^^^^ Steps blocks may only contain install step DSL calls: `mkdir`, `mkdir_p`, `touch`, `move`, `mv`, `move_children`, `symlink`, `ln_s`, `ln_sf`, `write`.
        end
      end
    CASK
  end

  it "reports an offense when cask steps contain formula rebuild actions" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight_steps do
          update_desktop_database
          ^^^^^^^^^^^^^^^^^^^^^^^ Steps blocks may only contain install step DSL calls: `mkdir`, `mkdir_p`, `touch`, `move`, `mv`, `move_children`, `symlink`, `ln_s`, `ln_sf`, `write`.
        end
      end
    CASK
  end

  it "accepts install step DSL calls" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        preflight_steps do
          mkdir_p "foo"
          touch "foo/state"
          mv "source", "target"
          move_children "source", "target"
          ln_sf "source", "target", source_base: :relative, uninstall: true
        end
      end
    CASK
  end

  it "autocorrects simple flight block file preparation" do
    expect_offense <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
        ^^^^^^^^^^^^^ Use `postflight_steps` for simple file preparation.
          (staged_path/"Prepared").mkpath
          FileUtils.touch staged_path/"Prepared/touched"
          FileUtils.mv staged_path/"source", staged_path/"target"
          FileUtils.ln_s "target", staged_path/"Linked"
        end
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight_steps do
          mkdir_p "Prepared"
          touch "Prepared/touched"
          mv "source", "target"
          ln_s "target", "Linked", source_base: :relative
        end
      end
    CASK
  end

  it "does not autocorrect non-file preparation in flight blocks" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          system_command "/usr/bin/true"
        end
      end
    CASK
  end

  it "does not autocorrect formula rebuild actions in flight blocks" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
        sha256 :no_check

        postflight do
          system Formula["desktop-file-utils"].opt_bin/"update-desktop-database", HOMEBREW_PREFIX/"share/applications"
        end
      end
    CASK
  end
end
