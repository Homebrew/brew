require 'test/unit/color'

module Test
  module Unit
    class ColorScheme
      include Enumerable

      TERM_256 = /
        [+-]256color|
        \A(?:
          alacritty|
          iTerm\s?\d*\.app|
          kitty|
          mintty|
          ms-terminal|
          nsterm-build\d+|
          nsterm|
          terminator|
          terminology(?:-[0-9.]+)?|
          termite|
          vscode
        )\z/x

      class << self
        def default
          if available_colors >= 256
            default_for_256_colors
          else
            default_for_8_colors
          end
        end

        @@default_for_8_colors = nil
        def default_for_8_colors
          @@default_for_8_colors ||=
            new("pass" => Color.new("green", :background => true) +
                          Color.new("white", :bold => true),
                "pass-marker" => Color.new("green", :bold => true),
                "failure" => Color.new("red", :background => true) +
                             Color.new("white", :bold => true),
                "failure-marker" => Color.new("red"),
                "pending" => Color.new("magenta", :background => true) +
                             Color.new("white", :bold => true),
                "pending-marker" => Color.new("magenta"),
                "omission" => Color.new("blue", :background => true) +
                             Color.new("white", :bold => true),
                "omission-marker" => Color.new("blue"),
                "notification" => Color.new("cyan", :background => true) +
                                  Color.new("white", :bold => true),
                "notification-marker" => Color.new("cyan"),
                "error" => Color.new("black", :background => true) +
                           Color.new("yellow", :bold => true),
                "error-marker" => Color.new("yellow"),
                "case" => Color.new("blue", :background => true) +
                          Color.new("white", :bold => true),
                "suite" => Color.new("green", :background => true) +
                           Color.new("white", :bold => true),
                "diff-inserted-tag" => Color.new("red", :background => true) +
                                       Color.new("black", :bold => true),
                "diff-deleted-tag" => Color.new("green", :background => true) +
                                      Color.new("black", :bold => true),
                "diff-difference-tag" => Color.new("cyan", :background => true) +
                                         Color.new("white", :bold => true),
                "diff-inserted" => Color.new("red", :background => true) +
                                   Color.new("white", :bold => true),
                "diff-deleted" =>  Color.new("green", :background => true) +
                                   Color.new("white", :bold => true))
        end

        @@default_for_256_colors = nil
        def default_for_256_colors
          @@default_for_256_colors ||=
            new("pass" => Color.new("030", :background => true) +
                          Color.new("555", :bold => true),
                "pass-marker" => Color.new("050", :bold => true),
                "failure" => Color.new("300", :background => true) +
                             Color.new("555", :bold => true),
                "failure-marker" => Color.new("500"),
                "pending" => Color.new("303", :background => true) +
                              Color.new("555", :bold => true),
                "pending-marker" => Color.new("303"),
                "omission" => Color.new("001", :background => true) +
                              Color.new("555", :bold => true),
                "omission-marker" => Color.new("001"),
                "notification" => Color.new("011", :background => true) +
                                  Color.new("555", :bold => true),
                "notification-marker" => Color.new("011"),
                "error" => Color.new("000", :background => true) +
                           Color.new("550", :bold => true),
                "error-marker" => Color.new("550"),
                "case" => Color.new("220", :background => true) +
                          Color.new("555", :bold => true),
                "suite" => Color.new("110", :background => true) +
                           Color.new("555", :bold => true),
                "diff-inserted-tag" => Color.new("500", :background => true) +
                                       Color.new("000", :bold => true),
                "diff-deleted-tag" => Color.new("050", :background => true) +
                                      Color.new("000", :bold => true),
                "diff-difference-tag" => Color.new("005", :background => true) +
                                         Color.new("555", :bold => true),
                "diff-inserted" => Color.new("300", :background => true) +
                                   Color.new("555", :bold => true),
                "diff-deleted" =>  Color.new("030", :background => true) +
                                   Color.new("555", :bold => true))
        end

        @@schemes = {}
        def all
          @@schemes.merge("default" => default)
        end

        def [](id)
          @@schemes[id.to_s]
        end

        def []=(id, scheme_or_spec)
          if scheme_or_spec.is_a?(self)
            scheme = scheme_or_spec
          else
            scheme = new(scheme_or_spec)
          end
          @@schemes[id.to_s] = scheme
        end

        def available_colors
          guess_available_colors_from_vte_version_env ||
            guess_available_colors_from_colorterm_env ||
            guess_available_colors_from_term_env ||
            8
        end

        private
        def guess_available_colors_from_vte_version_env
          vte_version = ENV["VTE_VERSION"]
          return nil if vte_version.nil?

          major = 0
          minor = 13
          micro = 0
          packed_version = major * 10000 + minor * 100 + micro
          if vte_version.to_i >= packed_version
            256
          else
            8
          end
        end

        def guess_available_colors_from_colorterm_env
          case ENV["COLORTERM"]
          when "gnome-terminal", "xfce4-terminal"
            256
          else
            nil
          end
        end

        def guess_available_colors_from_term_env
          case ENV["TERM"]
          when /[+-]direct/
            2**24
          when TERM_256
            256
          else
            nil
          end
        end
      end

      def initialize(scheme_spec)
        @scheme = {}
        scheme_spec.each do |key, color_spec|
          self[key] = color_spec
        end
      end

      def [](name)
        @scheme[name.to_s]
      end

      def []=(name, color_spec)
        @scheme[name.to_s] = make_color(color_spec)
      end

      def each(&block)
        @scheme.each(&block)
      end

      def to_hash
        hash = {}
        @scheme.each do |key, color|
          hash[key] = color
        end
        hash
      end

      private
      def make_color(color_spec)
        if color_spec.is_a?(Color) or color_spec.is_a?(MixColor)
          color_spec
        else
          color_name = nil
          normalized_color_spec = {}
          color_spec.each do |key, value|
            key = key.to_sym
            if key == :name
              color_name = value
            else
              normalized_color_spec[key] = value
            end
          end
          Color.new(color_name, normalized_color_spec)
        end
      end
    end
  end
end
