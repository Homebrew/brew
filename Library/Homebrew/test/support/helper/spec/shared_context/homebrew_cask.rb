# frozen_string_literal: true

require "cask/config"
require "cask/cache"

require "test/support/helper/cask/install_helper"
require "test/support/helper/cask/never_sudo_system_command"

module Cask
  class Config
    DEFAULT_DIRS_PATHNAMES = {
      appdir:               Pathname(TEST_TMPDIR)/"cask-appdir",
      keyboard_layoutdir:   Pathname(TEST_TMPDIR)/"cask-keyboard-layoutdir",
      prefpanedir:          Pathname(TEST_TMPDIR)/"cask-prefpanedir",
      qlplugindir:          Pathname(TEST_TMPDIR)/"cask-qlplugindir",
      mdimporterdir:        Pathname(TEST_TMPDIR)/"cask-mdimporter",
      dictionarydir:        Pathname(TEST_TMPDIR)/"cask-dictionarydir",
      fontdir:              Pathname(TEST_TMPDIR)/"cask-fontdir",
      colorpickerdir:       Pathname(TEST_TMPDIR)/"cask-colorpickerdir",
      servicedir:           Pathname(TEST_TMPDIR)/"cask-servicedir",
      input_methoddir:      Pathname(TEST_TMPDIR)/"cask-input_methoddir",
      internet_plugindir:   Pathname(TEST_TMPDIR)/"cask-internet_plugindir",
      audio_unit_plugindir: Pathname(TEST_TMPDIR)/"cask-audio_unit_plugindir",
      vst_plugindir:        Pathname(TEST_TMPDIR)/"cask-vst_plugindir",
      vst3_plugindir:       Pathname(TEST_TMPDIR)/"cask-vst3_plugindir",
      screen_saverdir:      Pathname(TEST_TMPDIR)/"cask-screen_saverdir",
    }.freeze

    remove_const :DEFAULT_DIRS
    DEFAULT_DIRS = DEFAULT_DIRS_PATHNAMES.transform_values(&:to_s).freeze
  end
end

# These shared contexts starting with `when` don't make sense.
RSpec.shared_context "Homebrew Cask", :needs_macos do # rubocop:disable RSpec/ContextWording
  around do |example|
    third_party_tap = Tap.fetch("third-party", "tap")

    begin
      Cask::Config::DEFAULT_DIRS_PATHNAMES.each_value(&:mkpath)

      CoreCaskTap.instance.tap do |tap|
        fixture_cask_dir = TEST_FIXTURE_DIR/"cask/Casks"
        fixture_cask_dir.glob("**/*.rb").each do |fixture_cask_path|
          relative_cask_path = fixture_cask_path.relative_path_from(fixture_cask_dir)

          # These are only used manually in tests since they
          # would otherwise conflict with other casks.
          next if relative_cask_path.dirname.basename.to_s == "outdated"

          cask_dir = (tap.cask_dir/relative_cask_path.dirname).tap(&:mkpath)
          FileUtils.ln_sf fixture_cask_path, cask_dir
        end

        tap.clear_cache
      end

      third_party_tap.tap do |tap|
        tap.path.parent.mkpath
        FileUtils.ln_sf TEST_FIXTURE_DIR/"third-party", tap.path

        tap.clear_cache
      end

      example.run
    ensure
      FileUtils.rm_rf Cask::Config::DEFAULT_DIRS_PATHNAMES.values
      FileUtils.rm_rf [Cask::Config.new.binarydir, Cask::Caskroom.path, Cask::Cache.path]
      FileUtils.rm_rf CoreCaskTap.instance.path
      FileUtils.rm_rf third_party_tap.path
      FileUtils.rm_rf third_party_tap.path.parent
    end
  end
end

RSpec.configure do |config|
  config.include_context "Homebrew Cask", :cask
end
