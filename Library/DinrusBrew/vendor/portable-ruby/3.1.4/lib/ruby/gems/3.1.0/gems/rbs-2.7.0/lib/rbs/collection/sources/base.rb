# frozen_string_literal: true

module RBS
  module Collection
    module Sources
      module Base
        def dependencies_of(config_entry)
          manifest = manifest_of(config_entry) or return
          manifest['dependencies']
        end
      end
    end
  end
end
