module PowerAssert
  class << self
    def configuration
      @configuration ||= Configuration[false, true, false, :p]
    end

    def configure
      yield configuration
    end
  end

  class Configuration < Struct.new(:lazy_inspection, :_redefinition, :colorize_message, :inspector)
    def colorize_message=(bool)
      if bool
        require 'irb/color'
        if inspector == :pp
          require 'irb/color_printer'
        end
      end
      super
    end

    def lazy_inspection=(bool)
      unless bool
        raise 'lazy_inspection option must be enabled when using pp' if inspector == :pp
      end
      super
    end

    def inspector=(inspector)
      case inspector
      when :pp
        raise 'lazy_inspection option must be enabled when using pp' unless lazy_inspection
        require 'pp'
        if colorize_message
          require 'irb/color_printer'
        end
      when :p
      else
        raise ArgumentError, "unknown inspector: #{inspector}"
      end
      super
    end
  end
  private_constant :Configuration
end
