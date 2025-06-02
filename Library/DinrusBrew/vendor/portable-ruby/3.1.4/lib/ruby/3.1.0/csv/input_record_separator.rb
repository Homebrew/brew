require "English"
require "stringio"

class CSV
  module InputRecordSeparator
    class << self
      if RUBY_VERSION >= "3.0.0"
        def value
          "\n"
        end
      else
        def value
          $INPUT_RECORD_SEPARATOR
        end
      end
    end
  end
end
