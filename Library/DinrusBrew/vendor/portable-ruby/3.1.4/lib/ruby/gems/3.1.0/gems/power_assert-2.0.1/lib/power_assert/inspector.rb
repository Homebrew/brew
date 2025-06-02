require 'power_assert/configuration'
require 'io/console/size'

module PowerAssert
  class InspectedValue
    def initialize(value)
      @value = value
    end

    def inspect
      @value
    end
  end
  private_constant :InspectedValue

  class SafeInspectable
    def initialize(value)
      @value = value
    end

    def inspect
      inspected = @value.inspect
      if Encoding.compatible?(Encoding.default_external, inspected)
        inspected
      else
        begin
          "#{inspected.encode(Encoding.default_external)}(#{inspected.encoding})"
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          inspected.force_encoding(Encoding.default_external)
        end
      end
    rescue => e
      "InspectionFailure: #{e.class}: #{e.message.each_line.first}"
    end
  end
  private_constant :SafeInspectable

  class Inspector
    def initialize(value, indent)
      @value = value
      @indent = indent
    end

    def inspect
      if PowerAssert.configuration.colorize_message
        if PowerAssert.configuration.inspector == :pp
          width = [IO.console_size[1] - 1 - @indent, 10].max
          IRB::ColorPrinter.pp(@value, '', width)
        else
          IRB::Color.colorize_code(@value.to_s, ignore_error: true)
        end
      else
        if PowerAssert.configuration.inspector == :pp
          PP.pp(@value, '')
        else
          @value.inspect
        end
      end
    end
  end
  private_constant :Inspector
end
