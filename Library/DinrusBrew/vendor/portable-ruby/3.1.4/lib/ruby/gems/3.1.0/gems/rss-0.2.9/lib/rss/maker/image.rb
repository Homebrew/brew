# frozen_string_literal: false
require_relative '../image'
require_relative '1.0'
require_relative 'dublincore'

module RSS
  module Maker
    module ImageItemModel
      def self.append_features(klass)
        super

        name = "#{RSS::IMAGE_PREFIX}_item"
        klass.def_classed_element(name)
      end

      def self.install_image_item(klass)
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          class ImageItem < ImageItemBase
            DublinCoreModel.install_dublin_core(self)
          end
EOC
      end

      class ImageItemBase < Base
        include Maker::DublinCoreModel

        attr_accessor :about, :resource, :image_width, :image_height
        add_need_initialize_variable("about")
        add_need_initialize_variable("resource")
        add_need_initialize_variable("image_width")
        add_need_initialize_variable("image_height")
        alias width= image_width=
        alias width image_width
        alias height= image_height=
        alias height image_height

        def have_required_values?
          @about
        end

        def to_feed(feed, current)
          if current.respond_to?(:image_item=) and have_required_values?
            item = current.class::ImageItem.new
            setup_values(item)
            setup_other_elements(item)
            current.image_item = item
          end
        end
      end
    end

    module ImageFaviconModel
      def self.append_features(klass)
        super

        name = "#{RSS::IMAGE_PREFIX}_favicon"
        klass.def_classed_element(name)
      end

      def self.install_image_favicon(klass)
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          class ImageFavicon < ImageFaviconBase
            DublinCoreModel.install_dublin_core(self)
          end
        EOC
      end

      class ImageFaviconBase < Base
        include Maker::DublinCoreModel

        attr_accessor :about, :image_size
        add_need_initialize_variable("about")
        add_need_initialize_variable("image_size")
        alias size image_size
        alias size= image_size=

        def have_required_values?
          @about and @image_size
        end

        def to_feed(feed, current)
          if current.respond_to?(:image_favicon=) and have_required_values?
            favicon = current.class::ImageFavicon.new
            setup_values(favicon)
            setup_other_elements(favicon)
            current.image_favicon = favicon
          end
        end
      end
    end

    class ChannelBase; include Maker::ImageFaviconModel; end

    class ItemsBase
      class ItemBase; include Maker::ImageItemModel; end
    end

    makers.each do |maker|
      maker.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        class Channel
          ImageFaviconModel.install_image_favicon(self)
        end

        class Items
          class Item
            ImageItemModel.install_image_item(self)
          end
        end
      EOC
    end
  end
end
