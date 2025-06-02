# frozen_string_literal: false
require_relative '../syndication'
require_relative '1.0'

module RSS
  module Maker
    module SyndicationModel
      def self.append_features(klass)
        super

        ::RSS::SyndicationModel::ELEMENTS.each do |name|
          klass.def_other_element(name)
        end
      end
    end

    class ChannelBase; include SyndicationModel; end
  end
end
