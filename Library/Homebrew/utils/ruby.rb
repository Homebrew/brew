# typed: strict
# frozen_string_literal: true

module Utils
  module Ruby
    module_function

    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T::Boolean) }
    def require?(path)
      return false if path.nil?

      if defined?(Warnings)
        Warnings.ignore(/already initialized constant/, /previous definition of/) do
          Kernel.require path.to_s
        end
      else
        Kernel.require path.to_s
      end
      true
    rescue LoadError
      false
    end
  end
end
