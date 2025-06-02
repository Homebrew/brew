# frozen_string_literal: true
module Psych
  class Exception < RuntimeError
  end

  class BadAlias < Exception
  end

  class DisallowedClass < Exception
    def initialize action, klass_name
      super "Tried to #{action} unspecified class: #{klass_name}"
    end
  end
end
