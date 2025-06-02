# frozen_string_literal: false
require 'rss/2.0'

module RSS
  # The prefix for the iTunes XML namespace.
  ITUNES_PREFIX = 'itunes'
  # The URI of the iTunes specification.
  ITUNES_URI = 'http://www.itunes.com/dtds/podcast-1.0.dtd'

  Rss.install_ns(ITUNES_PREFIX, ITUNES_URI)

  module ITunesModelUtils
    include Utils

    def def_class_accessor(klass, name, type, *args)
        normalized_name = name.gsub(/-/, "_")
      full_name = "#{ITUNES_PREFIX}_#{normalized_name}"
      klass_name = "ITunes#{Utils.to_class_name(normalized_name)}"

      case type
      when :element, :attribute
        klass::ELEMENTS << full_name
        def_element_class_accessor(klass, name, full_name, klass_name, *args)
      when :elements
        klass::ELEMENTS << full_name
        def_elements_class_accessor(klass, name, full_name, klass_name, *args)
      else
        klass.install_must_call_validator(ITUNES_PREFIX, ITUNES_URI)
        klass.install_text_element(normalized_name, ITUNES_URI, "?",
                                   full_name, type, name)
      end
    end

    def def_element_class_accessor(klass, name, full_name, klass_name,
                                   recommended_attribute_name=nil)
      klass.install_have_child_element(name, ITUNES_PREFIX, "?", full_name)
    end

    def def_elements_class_accessor(klass, name, full_name, klass_name,
                                    plural_name, recommended_attribute_name=nil)
      full_plural_name = "#{ITUNES_PREFIX}_#{plural_name}"
      klass.install_have_children_element(name, ITUNES_PREFIX, "*",
                                          full_name, full_plural_name)
    end
  end

  module ITunesBaseModel
    extend ITunesModelUtils

    ELEMENTS = []

    ELEMENT_INFOS = [["author"],
                     ["block", :yes_other],
                     ["explicit", :explicit_clean_other],
                     ["keywords", :csv],
                     ["subtitle"],
                     ["summary"]]
  end

  module ITunesChannelModel
    extend BaseModel
    extend ITunesModelUtils
    include ITunesBaseModel

    ELEMENTS = []

    class << self
      def append_features(klass)
        super

        return if klass.instance_of?(Module)
        ELEMENT_INFOS.each do |name, type, *additional_infos|
          def_class_accessor(klass, name, type, *additional_infos)
        end
      end
    end

    ELEMENT_INFOS = [
                     ["category", :elements, "categories", "text"],
                     ["image", :attribute, "href"],
                     ["owner", :element],
                     ["new-feed-url"],
                    ] + ITunesBaseModel::ELEMENT_INFOS

    class ITunesCategory < Element
      include RSS09

      @tag_name = "category"

      class << self
        def required_prefix
          ITUNES_PREFIX
        end

        def required_uri
          ITUNES_URI
        end
      end

      [
        ["text", "", true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      ITunesCategory = self
      install_have_children_element("category", ITUNES_URI, "*",
                                    "#{ITUNES_PREFIX}_category",
                                    "#{ITUNES_PREFIX}_categories")

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.text = args[0]
        end
      end

      def full_name
        tag_name_with_prefix(ITUNES_PREFIX)
      end

      private
      def maker_target(categories)
        if text or !itunes_categories.empty?
          categories.new_category
        else
          nil
        end
      end

      def setup_maker_attributes(category)
        category.text = text if text
      end

      def setup_maker_elements(category)
        super(category)
        itunes_categories.each do |sub_category|
          sub_category.setup_maker(category)
        end
      end
    end

    class ITunesImage < Element
      include RSS09

      @tag_name = "image"

      class << self
        def required_prefix
          ITUNES_PREFIX
        end

        def required_uri
          ITUNES_URI
        end
      end

      [
        ["href", "", true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.href = args[0]
        end
      end

      def full_name
        tag_name_with_prefix(ITUNES_PREFIX)
      end

      private
      def maker_target(target)
        if href
          target.itunes_image {|image| image}
        else
          nil
        end
      end

      def setup_maker_attributes(image)
        image.href = href
      end
    end

    class ITunesOwner < Element
      include RSS09

      @tag_name = "owner"

      class << self
        def required_prefix
          ITUNES_PREFIX
        end

        def required_uri
          ITUNES_URI
        end
      end

      install_must_call_validator(ITUNES_PREFIX, ITUNES_URI)
      [
        ["name"],
        ["email"],
      ].each do |name,|
        ITunesBaseModel::ELEMENT_INFOS << name
        install_text_element(name, ITUNES_URI, nil, "#{ITUNES_PREFIX}_#{name}")
      end

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.itunes_name = args[0]
          self.itunes_email = args[1]
        end
      end

      def full_name
        tag_name_with_prefix(ITUNES_PREFIX)
      end

      private
      def maker_target(target)
        target.itunes_owner
      end

      def setup_maker_element(owner)
        super(owner)
        owner.itunes_name = itunes_name
        owner.itunes_email = itunes_email
      end
    end
  end

  module ITunesItemModel
    extend BaseModel
    extend ITunesModelUtils
    include ITunesBaseModel

    class << self
      def append_features(klass)
        super

        return if klass.instance_of?(Module)
        ELEMENT_INFOS.each do |name, type|
          def_class_accessor(klass, name, type)
        end
      end
    end

    ELEMENT_INFOS = ITunesBaseModel::ELEMENT_INFOS +
      [["duration", :element, "content"], ["image", :attribute, "href"]]

    class ITunesImage < Element
      include RSS09

      @tag_name = "image"

      class << self
        def required_prefix
          ITUNES_PREFIX
        end

        def required_uri
          ITUNES_URI
        end
      end

      [
        ["href", "", true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required)
      end

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.href = args[0]
        end
      end

      def full_name
        tag_name_with_prefix(ITUNES_PREFIX)
      end

      private
      def maker_target(target)
        if href
          target.itunes_image {|image| image}
        else
          nil
        end
      end

      def setup_maker_attributes(image)
        image.href = href
      end
    end

    class ITunesDuration < Element
      include RSS09

      @tag_name = "duration"

      class << self
        def required_prefix
          ITUNES_PREFIX
        end

        def required_uri
          ITUNES_URI
        end

        def parse(duration, do_validate=true)
          if do_validate and /\A(?:
                                  \d?\d:[0-5]\d:[0-5]\d|
                                  [0-5]?\d:[0-5]\d|
                                  \d+
                                )\z/x !~ duration
            raise ArgumentError,
                    "must be one of HH:MM:SS, H:MM:SS, MM:SS, M:SS, S+: " +
                    duration.inspect
          end

          if duration.include?(':')
            components = duration.split(':')
            components[3..-1] = nil if components.size > 3

            components.unshift("00") until components.size == 3
            components.collect do |component|
              component.to_i
            end
          else
            seconds_to_components(duration.to_i)
          end
        end

        def construct(hours, minutes, seconds)
          components = [minutes, seconds]
          if components.include?(nil)
            nil
          else
            components.unshift(hours) if hours and hours > 0
            components.collect do |component|
              "%02d" % component
            end.join(':')
          end
        end

        private
        def seconds_to_components(total_seconds)
          hours = total_seconds / (60 * 60)
          minutes = (total_seconds / 60) % 60
          seconds = total_seconds % 60
          [hours, minutes, seconds]
        end
      end

      content_setup
      alias_method(:value, :content)
      remove_method(:content=)

      attr_reader :hour, :minute, :second
      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          args = args[0] if args.size == 1 and args[0].is_a?(Array)
          if args.size == 1
            self.content = args[0]
          elsif args.size > 3
            raise ArgumentError,
                    "must be (do_validate, params), (content), " +
                    "(minute, second), ([minute, second]), "  +
                    "(hour, minute, second) or ([hour, minute, second]): " +
                    args.inspect
          else
            @second, @minute, @hour = args.reverse
            update_content
          end
        end
      end

      def content=(value)
        if value.nil?
          @content = nil
        elsif value.is_a?(self.class)
          self.content = value.content
        else
          begin
            @hour, @minute, @second = self.class.parse(value, @do_validate)
          rescue ArgumentError
            raise NotAvailableValueError.new(tag_name, value)
          end
          @content = value
        end
      end
      alias_method(:value=, :content=)

      def hour=(hour)
        @hour = @do_validate ? Integer(hour) : hour.to_i
        update_content
        hour
      end

      def minute=(minute)
        @minute = @do_validate ? Integer(minute) : minute.to_i
        update_content
        minute
      end

      def second=(second)
        @second = @do_validate ? Integer(second) : second.to_i
        update_content
        second
      end

      def full_name
        tag_name_with_prefix(ITUNES_PREFIX)
      end

      private
      def update_content
        @content = self.class.construct(hour, minute, second)
      end

      def maker_target(target)
        if @content
          target.itunes_duration {|duration| duration}
        else
          nil
        end
      end

      def setup_maker_element(duration)
        super(duration)
        duration.content = @content
      end
    end
  end

  class Rss
    class Channel
      include ITunesChannelModel
      class Item; include ITunesItemModel; end
    end
  end

  element_infos =
    ITunesChannelModel::ELEMENT_INFOS + ITunesItemModel::ELEMENT_INFOS
  element_infos.each do |name, type|
    case type
    when :element, :elements, :attribute
      class_name = Utils.to_class_name(name)
      BaseListener.install_class_name(ITUNES_URI, name, "ITunes#{class_name}")
    else
      accessor_base = "#{ITUNES_PREFIX}_#{name.gsub(/-/, '_')}"
      BaseListener.install_get_text_element(ITUNES_URI, name, accessor_base)
    end
  end
end
