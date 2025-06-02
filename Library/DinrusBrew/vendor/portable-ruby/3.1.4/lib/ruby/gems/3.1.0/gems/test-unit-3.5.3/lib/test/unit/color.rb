module Test
  module Unit
    class Color
      class Error < StandardError
      end

      class ParseError < Error
      end

      class << self
        def parse_256_color(string)
          case string
          when /\A([0-5])([0-5])([0-5])\z/
            red, green, blue = $1, $2, $3
            red.to_i * 36 + green.to_i * 6 + blue.to_i + 16
          else
            message = "must be 'RGB' format and R, G and B " +
              "are in 0-5: #{string.inspect}"
            raise ParseError, message
          end
        end
      end

      NAMES = ["black", "red", "green", "yellow",
               "blue", "magenta", "cyan", "white"]

      attr_reader :name
      def initialize(name, options={})
        @name = name
        if options.has_key?(:foreground)
          if options[:foreground].nil?
            @background = false
          else
            @background = !options[:foreground]
          end
        else
          @background = options[:background]
        end
        @intensity = options[:intensity]
        @bold = options[:bold]
        @italic = options[:italic]
        @underline = options[:underline]
      end

      def foreground?
        not background?
      end

      def background?
        @background
      end

      def intensity?
        @intensity
      end

      def bold?
        @bold
      end

      def italic?
        @italic
      end

      def underline?
        @underline
      end

      def ==(other)
        self.class === other and
          [name, background?, intensity?,
           bold?, italic?, underline?] ==
          [other.name, other.background?, other.intensity?,
           other.bold?, other.italic?, other.underline?]
      end

      def sequence
        sequence = []
        if @name == "none"
        elsif @name == "reset"
          sequence << "0"
        else
          if NAMES.include?(@name)
            color_parameter = foreground? ? 3 : 4
            color_parameter += 6 if intensity?
            color = NAMES.index(@name)
            sequence << "#{color_parameter}#{color}"
          else
            sequence << (foreground? ? "38" : "48")
            sequence << "5"
            sequence << self.class.parse_256_color(@name).to_s
          end
        end
        sequence << "1" if bold?
        sequence << "3" if italic?
        sequence << "4" if underline?
        sequence
      end

      def escape_sequence
        "\e[#{sequence.join(';')}m"
      end

      def +(other)
        MixColor.new([self, other])
      end
    end

    class MixColor
      attr_reader :colors
      def initialize(colors)
        @colors = colors
      end

      def sequence
        @colors.inject([]) do |result, color|
          result + color.sequence
        end
      end

      def escape_sequence
        "\e[#{sequence.join(';')}m"
      end

      def +(other)
        self.class.new([self, other])
      end

      def ==(other)
        self.class === other and colors == other.colors
      end
    end
  end
end
