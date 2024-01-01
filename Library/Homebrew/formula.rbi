# typed: strict

# This file provides definitions for Forwardable#delegate, which is currently not supported by Sorbet.

class Formula
  def self.on_system_blocks_exist?; end
  # This method is included by `OnSystem`
  def self.on_macos(&block); end
end
