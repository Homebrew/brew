# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "irb"

module IRB
  def self.start_within(binding)
    old_stdout_sync = $stdout.sync
    $stdout.sync = true

    unless @setup_done
      setup(nil, argv: [])
      @setup_done = true
    end

    workspace = WorkSpace.new(binding)
    irb = Irb.new(workspace)
    irb.run(conf)
  ensure
    $stdout.sync = old_stdout_sync
  end
end
