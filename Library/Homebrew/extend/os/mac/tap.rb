# typed: true
# frozen_string_literal: true

class Tap
  def self.install_default_cask_tap_if_necessary(force: false)
    odisabled "Tap.install_default_cask_tap_if_necessary", "CoreCaskTap.ensure_installed!"

    cask_tap = CoreCaskTap.instance
    return false if cask_tap.installed?
    return false unless Homebrew::EnvConfig.no_install_from_api?
    return false if Homebrew::EnvConfig.automatically_set_no_install_from_api?
    return false if !force && Tap.untapped_official_taps.include?(cask_tap.name)

    cask_tap.install
    true
  end
end
