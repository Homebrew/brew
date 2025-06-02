# frozen_string_literal: false
require 'rss/1.0'
require_relative 'dublincore'

module RSS

  # The prefix for the Image XML namespace.
  IMAGE_PREFIX = 'image'
  # The URI for the Image specification.
  IMAGE_URI = 'http://purl.org/rss/1.0/modules/image/'

  RDF.install_ns(IMAGE_PREFIX, IMAGE_URI)

  # This constant holds strings which contain the names of
  # image elements, with the appropriate prefix.
  IMAGE_ELEMENTS = []

  %w(item favicon).each do |name|
    class_name = Utils.to_class_name(name)
    BaseListener.install_class_name(IMAGE_URI, name, "Image#{class_name}")
    IMAGE_ELEMENTS << "#{IMAGE_PREFIX}_#{name}"
  end

  module ImageModelUtils
    def validate_one_tag_name(ignore_unknown_element, name, tags)
      if !ignore_unknown_element
        invalid = tags.find {|tag| tag != name}
        raise UnknownTagError.new(invalid, IMAGE_URI) if invalid
      end
      raise TooMuchTagError.new(name, tag_name) if tags.size > 1
    end
  end

  module ImageItemModel
    include ImageModelUtils
    extend BaseModel

    def self.append_features(klass)
      super

      klass.install_have_child_element("item", IMAGE_URI, "?",
                                       "#{IMAGE_PREFIX}_item")
      klass.install_must_call_validator(IMAGE_PREFIX, IMAGE_URI)
    end

    class ImageItem < Element
      include RSS10
      include DublinCoreModel

      @tag_name = "item"

      class << self
        def required_prefix
          IMAGE_PREFIX
        end

        def required_uri
          IMAGE_URI
        end
      end

      install_must_call_validator(IMAGE_PREFIX, IMAGE_URI)

      [
        ["about", ::RSS::RDF::URI, true],
        ["resource", ::RSS::RDF::URI, false],
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required, nil, nil,
                              "#{::RSS::RDF::PREFIX}:#{name}")
      end

      %w(width height).each do |tag|
        full_name = "#{IMAGE_PREFIX}_#{tag}"
        disp_name = "#{IMAGE_PREFIX}:#{tag}"
        install_text_element(tag, IMAGE_URI, "?",
                             full_name, :integer, disp_name)
        BaseListener.install_get_text_element(IMAGE_URI, tag, full_name)
      end

      alias width= image_width=
      alias width image_width
      alias height= image_height=
      alias height image_height

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.about = args[0]
          self.resource = args[1]
        end
      end

      def full_name
        tag_name_with_prefix(IMAGE_PREFIX)
      end

      private
      def maker_target(target)
        target.image_item
      end

      def setup_maker_attributes(item)
        item.about = self.about
        item.resource = self.resource
      end
    end
  end

  module ImageFaviconModel
    include ImageModelUtils
    extend BaseModel

    def self.append_features(klass)
      super

      unless klass.class == Module
        klass.install_have_child_element("favicon", IMAGE_URI, "?",
                                         "#{IMAGE_PREFIX}_favicon")
        klass.install_must_call_validator(IMAGE_PREFIX, IMAGE_URI)
      end
    end

    class ImageFavicon < Element
      include RSS10
      include DublinCoreModel

      @tag_name = "favicon"

      class << self
        def required_prefix
          IMAGE_PREFIX
        end

        def required_uri
          IMAGE_URI
        end
      end

      [
        ["about", ::RSS::RDF::URI, true, ::RSS::RDF::PREFIX],
        ["size", IMAGE_URI, true, IMAGE_PREFIX],
      ].each do |name, uri, required, prefix|
        install_get_attribute(name, uri, required, nil, nil,
                              "#{prefix}:#{name}")
      end

      AVAILABLE_SIZES = %w(small medium large)
      alias_method :set_size, :size=
      private :set_size
      def size=(new_value)
        if @do_validate and !new_value.nil?
          new_value = new_value.strip
          unless AVAILABLE_SIZES.include?(new_value)
            attr_name = "#{IMAGE_PREFIX}:size"
            raise NotAvailableValueError.new(full_name, new_value, attr_name)
          end
        end
        set_size(new_value)
      end

      alias image_size= size=
      alias image_size size

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.about = args[0]
          self.size = args[1]
        end
      end

      def full_name
        tag_name_with_prefix(IMAGE_PREFIX)
      end

      private
      def maker_target(target)
        target.image_favicon
      end

      def setup_maker_attributes(favicon)
        favicon.about = self.about
        favicon.size = self.size
      end
    end

  end

  class RDF
    class Channel; include ImageFaviconModel; end
    class Item; include ImageItemModel; end
  end

end
