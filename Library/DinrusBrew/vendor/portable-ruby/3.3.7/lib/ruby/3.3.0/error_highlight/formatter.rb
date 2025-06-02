module ErrorHighlight
  class DefaultFormatter
    def self.message_for(spot)
      # currently only a one-line code snippet is supported
      if spot[:first_lineno] == spot[:last_lineno]
        indent = spot[:snippet][0...spot[:first_column]].gsub(/[^\t]/, " ")
        marker = indent + "^" * (spot[:last_column] - spot[:first_column])

        "\n\n#{ spot[:snippet] }#{ marker }"
      else
        ""
      end
    end
  end

  def self.formatter
    Ractor.current[:__error_highlight_formatter__] || DefaultFormatter
  end

  def self.formatter=(formatter)
    Ractor.current[:__error_highlight_formatter__] = formatter
  end
end
