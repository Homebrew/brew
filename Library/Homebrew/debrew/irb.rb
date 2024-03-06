# typed: true
# frozen_string_literal: true

require "irb"

module IRB
  def self.start_within(binding)
    unless @setup_done
      setup(nil, argv: [])
      @setup_done = true
    end

    workspace = WorkSpace.new(binding)
    irb = Irb.new(workspace)

    @CONF[:IRB_RC]&.call(irb.context)
    @CONF[:MAIN_CONTEXT] = irb.context

    prev_trap = trap("SIGINT") do
      irb.signal_handle
    end

    begin
      catch(:IRB_EXIT) do
        irb.eval_input
      end
    ensure
      trap("SIGINT", prev_trap)
      irb_at_exit
    end
  end
end
