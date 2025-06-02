# frozen_string_literal: true

module RBS
  module Test
    module Observer
      @@observers = {}

      class <<self
        def notify(key, *args)
          @@observers[key]&.call(*args)
        end

        def register(key, object = nil, &block)
          @@observers[key] = object || block
        end
      end
    end
  end
end
