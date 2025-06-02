# frozen_string_literal: true

class Logger
  # not used after 1.2.7. just for compat.
  class Error < RuntimeError # :nodoc:
  end
  class ShiftingError < Error # :nodoc:
  end
end
