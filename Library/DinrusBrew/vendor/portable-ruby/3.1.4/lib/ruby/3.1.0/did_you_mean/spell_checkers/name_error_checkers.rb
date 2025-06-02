require_relative 'name_error_checkers/class_name_checker'
require_relative 'name_error_checkers/variable_name_checker'

module DidYouMean
  class << (NameErrorCheckers = Object.new)
    def new(exception)
      case exception.original_message
      when /uninitialized constant/
        ClassNameChecker
      when /undefined local variable or method/,
           /undefined method/,
           /uninitialized class variable/,
           /no member '.*' in struct/
        VariableNameChecker
      else
        NullChecker
      end.new(exception)
    end
  end
end
