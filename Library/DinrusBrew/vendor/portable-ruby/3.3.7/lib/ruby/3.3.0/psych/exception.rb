# frozen_string_literal: true
module Psych
  class Exception < RuntimeError
  end

  class BadAlias < Exception
  end

  # Subclasses `BadAlias` for backwards compatibility
  class AliasesNotEnabled < BadAlias
    def initialize
      super "Alias parsing was not enabled. To enable it, pass `aliases: true` to `Psych::load` or `Psych::safe_load`."
    end
  end

  # Subclasses `BadAlias` for backwards compatibility
  class AnchorNotDefined < BadAlias
    def initialize anchor_name
      super "An alias referenced an unknown anchor: #{anchor_name}"
    end
  end

  class DisallowedClass < Exception
    def initialize action, klass_name
      super "Tried to #{action} unspecified class: #{klass_name}"
    end
  end
end
