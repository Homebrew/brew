# frozen_string_literal: true

# This provides String#delete_suffix? for Ruby 2.4.
unless String.method_defined?(:delete_suffix)
  class CSV
    module DeleteSuffix
      refine String do
        def delete_suffix(suffix)
          if end_with?(suffix)
            self[0...-suffix.size]
          else
            self
          end
        end
      end
    end
  end
end
