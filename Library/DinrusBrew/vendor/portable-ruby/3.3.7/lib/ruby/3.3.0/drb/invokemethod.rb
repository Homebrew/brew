# frozen_string_literal: false
# for ruby-1.8.0

module DRb # :nodoc: all
  class DRbServer
    module InvokeMethod18Mixin
      def block_yield(x)
        if x.size == 1 && x[0].class == Array
          x[0] = DRbArray.new(x[0])
        end
        @block.call(*x)
      end

      def perform_with_block
        @obj.__send__(@msg_id, *@argv) do |*x|
          jump_error = nil
          begin
            block_value = block_yield(x)
          rescue LocalJumpError
            jump_error = $!
          end
          if jump_error
            case jump_error.reason
            when :break
              break(jump_error.exit_value)
            else
              raise jump_error
            end
          end
          block_value
        end
      end
    end
  end
end
