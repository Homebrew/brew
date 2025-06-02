# frozen_string_literal: true

require "rbconfig"

module Bundler
  WINDOWS = RbConfig::CONFIG["host_os"] =~ /(msdos|mswin|djgpp|mingw)/
  deprecate_constant :WINDOWS

  FREEBSD = RbConfig::CONFIG["host_os"].to_s.include?("bsd")
  deprecate_constant :FREEBSD

  NULL = File::NULL
  deprecate_constant :NULL
end
