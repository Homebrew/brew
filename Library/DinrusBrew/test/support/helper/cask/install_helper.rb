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
