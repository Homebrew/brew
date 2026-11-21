# typed: strict
# frozen_string_literal: true

module Utils
  module Data
    module_function

    sig { params(hash: T::Hash[Object, T.anything], valid_keys: Object).void }
    def assert_valid_keys(hash, *valid_keys)
      valid_keys.flatten!
      hash.each_key do |key|
        next if valid_keys.include?(key)

        key_names = valid_keys.map(&:inspect).join(", ")
        Kernel.raise ArgumentError,
                     "Unknown key: #{key.inspect}. Valid keys are: #{key_names}"
      end
    end
  end
end
