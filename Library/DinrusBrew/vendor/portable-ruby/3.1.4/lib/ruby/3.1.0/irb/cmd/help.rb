# frozen_string_literal: false
#
#   help.rb - helper using ri
#   	$Release Version: 0.9.6$
#   	$Revision$
#
# --
#
#
#

require_relative "nop"

# :stopdoc:
module IRB
  module ExtendCommand
    class Help < Nop
      def execute(*names)
        require 'rdoc/ri/driver'
        opts = RDoc::RI::Driver.process_args([])
        IRB::ExtendCommand::Help.const_set(:Ri, RDoc::RI::Driver.new(opts))
      rescue LoadError, SystemExit
        IRB::ExtendCommand::Help.remove_method(:execute)
        # raise NoMethodError in ensure
      else
        def execute(*names)
          if names.empty?
            Ri.interactive
            return
          end
          names.each do |name|
            begin
              Ri.display_name(name.to_s)
            rescue RDoc::RI::Error
              puts $!.message
            end
          end
          nil
        end
        nil
      ensure
        execute(*names)
      end
    end
  end
end
# :startdoc:
