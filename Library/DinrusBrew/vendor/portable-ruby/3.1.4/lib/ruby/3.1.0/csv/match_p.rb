# frozen_string_literal: true

# This provides String#match? and Regexp#match? for Ruby 2.3.
unless String.method_defined?(:match?)
  class CSV
    module MatchP
      refine String do
        def match?(pattern)
          self =~ pattern
        end
      end

      refine Regexp do
        def match?(string)
          self =~ string
        end
      end
    end
  end
end
