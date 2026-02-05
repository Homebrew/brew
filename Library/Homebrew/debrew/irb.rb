# typed: strict
# frozen_string_literal: true

require "irb"

module IRB
  sig { params(binding: Binding).void }
  def self.start_within(binding)
    old_stdout_sync = $stdout.sync
    $stdout.sync = true

    @setup_done ||= T.let(false, T.nilable(T::Boolean))
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
