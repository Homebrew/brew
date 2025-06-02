# frozen_string_literal: false
#
#   irb/help.rb - print usage module
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#
#
#

require_relative 'magic-file'

module IRB
  # Outputs the irb help message, see IRB@Command+line+options.
  def IRB.print_usage
    lc = IRB.conf[:LC_MESSAGES]
    path = lc.find("irb/help-message")
    space_line = false
    IRB::MagicFile.open(path){|f|
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
