# frozen_string_literal: true

cask "pre-receipt-rb" do
  version "1.0"
  sha256 :no_check

  url "https://example.com/pre-receipt-rb.zip"
  name "Pre-Receipt Ruby"
  homepage "https://example.com/pre-receipt-rb"

  app "Pre Receipt Rb.app"
end
