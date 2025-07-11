# frozen_string_literal: true

require "require-hooks/api"

mode = ENV["REQUIRE_HOOKS_MODE"]

case mode
when "patch"
  require "require-hooks/mode/kernel_patch"
when "load_iseq"
  require "require-hooks/mode/load_iseq"
when "bootsnap"
  require "require-hooks/mode/bootsnap"
else
  if defined?(::RubyVM::InstructionSequence)
    # Check if Bootsnap has been loaded.
    # Based on https://github.com/kddeisz/preval/blob/master/lib/preval.rb
    if RubyVM::InstructionSequence.respond_to?(:load_iseq) &&
        (load_iseq = RubyVM::InstructionSequence.method(:load_iseq)) &&
        load_iseq.source_location[0].include?("/bootsnap/")
      require "require-hooks/mode/bootsnap"
    else
      require "require-hooks/mode/load_iseq"
    end
  else
    require "require-hooks/mode/kernel_patch"
  end
end
