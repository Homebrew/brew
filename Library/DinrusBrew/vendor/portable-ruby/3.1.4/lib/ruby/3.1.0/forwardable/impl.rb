# :stopdoc:
module Forwardable
  def self._valid_method?(method)
    iseq = RubyVM::InstructionSequence.compile("().#{method}", nil, nil, 0, false)
  rescue SyntaxError
    false
  else
    iseq.to_a.dig(-1, 1, 1, :mid) == method.to_sym
  end

  def self._compile_method(src, file, line)
    RubyVM::InstructionSequence.compile(src, file, file, line,
               trace_instruction: false)
      .eval
  end
end
