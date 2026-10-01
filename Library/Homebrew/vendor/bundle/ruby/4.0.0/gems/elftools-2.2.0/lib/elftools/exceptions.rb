# frozen_string_literal: true

module ELFTools
  # Being raised when parsing error.
  class ELFError < StandardError; end

  # Raised on invalid ELF magic.
  class ELFMagicError < ELFError; end

  # Raised on invalid ELF class (EI_CLASS).
  class ELFClassError < ELFError; end

  # Raised on invalid ELF data encoding (EI_DATA).
  class ELFDataError < ELFError; end
end
