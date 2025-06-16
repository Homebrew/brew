# typed: strict
# frozen_string_literal: true

require "optparse"

OptionParser.accept Pathname do |path|
  Pathname(path).expand_path if path
end
