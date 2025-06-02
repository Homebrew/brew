# frozen_string_literal: false
require_relative '../content'
require_relative '1.0'
require_relative '2.0'

module RSS
  module Maker
    module ContentModel
      def self.append_features(klass)
        super

        ::RSS::ContentModel::ELEMENTS.each do |name|
          klass.def_other_element(name)
        end
      end
    end

    class ItemsBase
      class ItemBase; include ContentModel; end
    end
  end
end
