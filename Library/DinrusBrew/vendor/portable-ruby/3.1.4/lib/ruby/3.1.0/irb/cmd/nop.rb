# frozen_string_literal: false
#
#   nop.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
# :stopdoc:
module IRB
  module ExtendCommand
    class Nop

      if RUBY_ENGINE == "ruby" && RUBY_VERSION >= "2.7.0"
        def self.execute(conf, *opts, **kwargs, &block)
          command = new(conf)
          command.execute(*opts, **kwargs, &block)
        end
      else
        def self.execute(conf, *opts, &block)
          command = new(conf)
          command.execute(*opts, &block)
        end
      end

      def initialize(conf)
        @irb_context = conf
      end

      attr_reader :irb_context

      def irb
        @irb_context.irb
      end

      def execute(*opts)
        #nop
      end
    end
  end
end
# :startdoc:
