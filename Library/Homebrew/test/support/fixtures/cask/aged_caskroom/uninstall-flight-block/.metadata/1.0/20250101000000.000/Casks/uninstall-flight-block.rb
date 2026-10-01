# frozen_string_literal: true

cask "uninstall-flight-block" do
  version "1.0"
  sha256 :no_check

  url "https://example.com/uninstall-flight-block.zip"
  name "Uninstall Flight Block"
  homepage "https://example.com/uninstall-flight-block"

  app "Uninstall Flight Block.app"

  uninstall_preflight do
    # do nothing
  end
end
