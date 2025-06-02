# frozen_string_literal: true
#
#   irb/help.rb - print usage module
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#

module IRB
  # Outputs the irb help message, see IRB@Command-Line+Options.
  def IRB.print_usage # :nodoc:
    lc = IRB.conf[:LC_MESSAGES]
    path = lc.find("irb/help-message")
    space_line = false
    File.open(path){|f|
      f.each_line do |l|
        if /^\s*$/ =~ l
          lc.puts l unless space_line
          space_line = true
          next
        end
        space_line = false

        l.sub!(/#.*$/, "")
        next if /^\s*$/ =~ l
        lc.puts l
      end
    }
  end
end
