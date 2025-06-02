begin
  require "readline.#{RbConfig::CONFIG["DLEXT"]}"
rescue LoadError
  require 'reline' unless defined? Reline
  Object.send(:remove_const, :Readline) if Object.const_defined?(:Readline)
  Readline = Reline
end
