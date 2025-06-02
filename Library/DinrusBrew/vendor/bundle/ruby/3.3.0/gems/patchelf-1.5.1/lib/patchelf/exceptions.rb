# encoding: ascii-8bit
# frozen_string_literal: true

require 'elftools/exceptions'

module PatchELF
  # Raised on an error during ELF modification.
  class PatchError < ELFTools::ELFError; end

  # Raised when Dynamic Tag is missing
  class MissingTagError < PatchError; end

  # Raised on missing Program Header(segment)
  class MissingSegmentError < PatchError; end
end
