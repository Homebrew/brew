# frozen_string_literal: true

# not used after 1.2.7. just for compat.
class Logger
  class Error < RuntimeError # :nodoc:
  end
  class ShiftingError < Error # :nodoc:
  end
end
