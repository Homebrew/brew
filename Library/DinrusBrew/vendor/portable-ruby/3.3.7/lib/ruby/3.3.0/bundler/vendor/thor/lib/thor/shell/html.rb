require_relative "basic"

class Bundler::Thor
  module Shell
    # Inherit from Bundler::Thor::Shell::Basic and add set_color behavior. Check
    # Bundler::Thor::Shell::Basic to see all available methods.
    #
    class HTML < Basic
      # The start of an HTML bold sequence.
      BOLD       = "font-weight: bold"

      # Set the terminal's foreground HTML color to black.
      BLACK      = "color: black"
      # Set the terminal's foreground HTML color to red.
      RED        = "color: red"
      # Set the terminal's foreground HTML color to green.
      GREEN      = "color: green"
      # Set the terminal's foreground HTML color to yellow.
      YELLOW     = "color: yellow"
      # Set the terminal's foreground HTML color to blue.
      BLUE       = "color: blue"
      # Set the terminal's foreground HTML color to magenta.
      MAGENTA    = "color: magenta"
      # Set the terminal's foreground HTML color to cyan.
      CYAN       = "color: cyan"
      # Set the terminal's foreground HTML color to white.
      WHITE      = "color: white"

      # Set the terminal's background HTML color to black.
      ON_BLACK   = "background-color: black"
      # Set the terminal's background HTML color to red.
      ON_RED     = "background-color: red"
      # Set the terminal's background HTML color to green.
      ON_GREEN   = "background-color: green"
      # Set the terminal's background HTML color to yellow.
      ON_YELLOW  = "background-color: yellow"
      # Set the terminal's background HTML color to blue.
      ON_BLUE    = "background-color: blue"
      # Set the terminal's background HTML color to magenta.
      ON_MAGENTA = "background-color: magenta"
      # Set the terminal's background HTML color to cyan.
      ON_CYAN    = "background-color: cyan"
      # Set the terminal's background HTML color to white.
      ON_WHITE   = "background-color: white"

      # Set color by using a string or one of the defined constants. If a third
      # option is set to true, it also adds bold to the string. This is based
      # on Highline implementation and it automatically appends CLEAR to the end
      # of the returned String.
      #
      def set_color(string, *colors)
        if colors.all? { |color| color.is_a?(Symbol) || color.is_a?(String) }
          html_colors = colors.map { |color| lookup_color(color) }
          "<span style=\"#{html_colors.join('; ')};\">#{Bundler::Thor::Util.escape_html(string)}</span>"
        else
          color, bold = colors
          html_color = self.class.const_get(color.to_s.upcase) if color.is_a?(Symbol)
          styles = [html_color]
          styles << BOLD if bold
          "<span style=\"#{styles.join('; ')};\">#{Bundler::Thor::Util.escape_html(string)}</span>"
        end
      end

      # Ask something to the user and receives a response.
      #
      # ==== Example
      # ask("What is your name?")
      #
      # TODO: Implement #ask for Bundler::Thor::Shell::HTML
      def ask(statement, color = nil)
        raise NotImplementedError, "Implement #ask for Bundler::Thor::Shell::HTML"
      end

    protected

      def can_display_colors?
        true
      end
    end
  end
end
