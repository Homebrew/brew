# typed: true
# frozen_string_literal: true

module Homebrew
  sig { returns(T::Array[String]) }
  def self.tar_args
    if MacOS.version >= :catalina
      ["--no-mac-metadata", "--no-acls", "--no-xattrs"].freeze
    else
      [].freeze
    end
  end

  sig { params(gnu_tar_formula: Formula).returns(String) }
  def self.gnu_tar(gnu_tar_formula)
    "#{gnu_tar_formula.opt_bin}/gtar"
  end
end
