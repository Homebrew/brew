# typed: true
# frozen_string_literal: true

require "cask/installer"

module InstallHelper
  module_function

  def self.install_without_artifacts(cask)
    Cask::Installer.new(cask).tap do |i|
      i.download
      i.extract_primary_container
    end
  end

  def self.install_without_artifacts_with_caskfile(cask)
    Cask::Installer.new(cask).tap do |i|
      i.download
      i.extract_primary_container
      i.save_caskfile
    end
  end

  # Creates a minimal stub installation without downloading or extracting.
  # This is useful for tests that only need to check installation state
  # (installed?, installed_version) and artifact paths without performing
  # actual file operations.
  #
  # @param cask [Cask::Cask] the cask to stub install
  # @param create_app_dirs [Boolean] whether to create stub app directories in appdir
  def self.stub_cask_installation(cask, create_app_dirs: true)
    # Create the caskroom path
    cask.caskroom_path.mkpath

    # Create the staged_path (version directory)
    cask.staged_path.mkpath

    # Create metadata directory structure and save caskfile
    # This makes installed? and installed_version work
    Cask::Installer.new(cask).save_caskfile

    return unless create_app_dirs

    # Create stub app directories in appdir so path existence checks pass
    cask.artifacts.each do |artifact|
      next unless artifact.is_a?(Cask::Artifact::App)

      target_path = cask.config.appdir.join(artifact.target.basename)
      target_path.mkpath
    end
  end

  def install_without_artifacts(cask)
    Cask::Installer.new(cask).tap do |i|
      i.download
      i.extract_primary_container
    end
  end

  def install_with_caskfile(cask)
    Cask::Installer.new(cask).tap(&:save_caskfile)
  end
end
