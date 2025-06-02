# frozen_string_literal: false
#
#   load.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require_relative "nop"
require_relative "../ext/loader"

# :stopdoc:
module IRB
  module ExtendCommand
    class Load < Nop
      include IrbLoader

      def execute(file_name, priv = nil)
        return irb_load(file_name, priv)
      end
    end

    class Require < Nop
      include IrbLoader

      def execute(file_name)

        rex = Regexp.new("#{Regexp.quote(file_name)}(\.o|\.rb)?")
        return false if $".find{|f| f =~ rex}

        case file_name
        when /\.rb$/
          begin
            if irb_load(file_name)
              $".push file_name
              return true
            end
          rescue LoadError
          end
        when /\.(so|o|sl)$/
          return ruby_require(file_name)
        end

        begin
          irb_load(f = file_name + ".rb")
          $".push f
          return true
        rescue LoadError
          return ruby_require(file_name)
        end
      end
    end

    class Source < Nop
      include IrbLoader
      def execute(file_name)
        source_file(file_name)
      end
    end
  end

end
# :startdoc:
