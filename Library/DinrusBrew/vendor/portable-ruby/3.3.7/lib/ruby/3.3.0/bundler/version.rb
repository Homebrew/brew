# frozen_string_literal: false

module Bundler
  VERSION = "2.5.22".freeze

  def self.bundler_major_version
    @bundler_major_version ||= VERSION.split(".").first.to_i
  end

  def self.gem_version
    @gem_version ||= Gem::Version.create(VERSION)
  end
end
