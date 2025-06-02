begin
  require 'readline.so'
rescue LoadError
  require 'reline' unless defined? Reline
  Object.send(:remove_const, :Readline) if Object.const_defined?(:Readline)
  Readline = Reline
end
