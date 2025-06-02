# frozen_string_literal: false
require_relative '../itunes'
require_relative '2.0'

module RSS
  module Maker
    module ITunesBaseModel
      def def_class_accessor(klass, name, type, *args)
        name = name.gsub(/-/, "_").gsub(/^itunes_/, '')
        full_name = "#{RSS::ITUNES_PREFIX}_#{name}"
        case type
        when nil
          klass.def_other_element(full_name)
        when :yes_other
          def_yes_other_accessor(klass, full_name)
        when :explicit_clean_other
          def_explicit_clean_other_accessor(klass, full_name)
        when :csv
          def_csv_accessor(klass, full_name)
        when :element, :attribute
          recommended_attribute_name, = *args
          klass_name = "ITunes#{Utils.to_class_name(name)}"
          klass.def_classed_element(full_name, klass_name,
                                    recommended_attribute_name)
        when :elements
          plural_name, recommended_attribute_name = args
          plural_name ||= "#{name}s"
          full_plural_name = "#{RSS::ITUNES_PREFIX}_#{plural_name}"
          klass_name = "ITunes#{Utils.to_class_name(name)}"
          plural_klass_name = "ITunes#{Utils.to_class_name(plural_name)}"
          def_elements_class_accessor(klass, name, full_name, full_plural_name,
                                      klass_name, plural_klass_name,
                                      recommended_attribute_name)
        end
      end

      def def_yes_other_accessor(klass, full_name)
        klass.def_other_element(full_name)
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          def #{full_name}?
            Utils::YesOther.parse(@#{full_name})
          end
        EOC
      end

      def def_explicit_clean_other_accessor(klass, full_name)
        klass.def_other_element(full_name)
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          def #{full_name}?
            Utils::ExplicitCleanOther.parse(#{full_name})
          end
        EOC
      end

      def def_csv_accessor(klass, full_name)
        klass.def_csv_element(full_name)
      end

      def def_elements_class_accessor(klass, name, full_name, full_plural_name,
                                      klass_name, plural_klass_name,
                                      recommended_attribute_name=nil)
        if recommended_attribute_name
          klass.def_classed_elements(full_name, recommended_attribute_name,
                                     plural_klass_name, full_plural_name)
        else
          klass.def_classed_element(full_plural_name, plural_klass_name)
        end
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          def new_#{full_name}(text=nil)
            #{full_name} = @#{full_plural_name}.new_#{name}
            #{full_name}.text = text
            if block_given?
              yield #{full_name}
            else
              #{full_name}
            end
          end
        EOC
      end
    end

    module ITunesChannelModel
      extend ITunesBaseModel

      class << self
        def append_features(klass)
          super

          ::RSS::ITunesChannelModel::ELEMENT_INFOS.each do |name, type, *args|
            def_class_accessor(klass, name, type, *args)
          end
        end
      end

      class ITunesCategoriesBase < Base
        def_array_element("category", "itunes_categories",
                          "ITunesCategory")
        class ITunesCategoryBase < Base
          attr_accessor :text
          add_need_initialize_variable("text")
          def_array_element("category", "itunes_categories",
                            "ITunesCategory")

          def have_required_values?
            text
          end

          alias_method :to_feed_for_categories, :to_feed
          def to_feed(feed, current)
            if text and current.respond_to?(:itunes_category)
              new_item = current.class::ITunesCategory.new(text)
              to_feed_for_categories(feed, new_item)
              current.itunes_categories << new_item
            end
          end
        end
      end

      class ITunesImageBase < Base
        add_need_initialize_variable("href")
        attr_accessor("href")

        def to_feed(feed, current)
          if @href and current.respond_to?(:itunes_image)
            current.itunes_image ||= current.class::ITunesImage.new
            current.itunes_image.href = @href
          end
        end
      end

      class ITunesOwnerBase < Base
        %w(itunes_name itunes_email).each do |name|
          add_need_initialize_variable(name)
          attr_accessor(name)
        end

        def to_feed(feed, current)
          if current.respond_to?(:itunes_owner=)
            _not_set_required_variables = not_set_required_variables
            if (required_variable_names - _not_set_required_variables).empty?
              return
            end

            unless have_required_values?
              raise NotSetError.new("maker.channel.itunes_owner",
                                    _not_set_required_variables)
            end
            current.itunes_owner ||= current.class::ITunesOwner.new
            current.itunes_owner.itunes_name = @itunes_name
            current.itunes_owner.itunes_email = @itunes_email
          end
        end

        private
        def required_variable_names
          %w(itunes_name itunes_email)
        end
      end
    end

    module ITunesItemModel
      extend ITunesBaseModel

      class << self
        def append_features(klass)
          super

          ::RSS::ITunesItemModel::ELEMENT_INFOS.each do |name, type, *args|
            def_class_accessor(klass, name, type, *args)
          end
        end
      end

      class ITunesImageBase < Base
        add_need_initialize_variable("href")
        attr_accessor("href")

        def to_feed(feed, current)
          if @href and current.respond_to?(:itunes_image)
            current.itunes_image ||= current.class::ITunesImage.new
            current.itunes_image.href = @href
          end
        end
      end

      class ITunesDurationBase < Base
        attr_reader :content
        add_need_initialize_variable("content")

        %w(hour minute second).each do |name|
          attr_reader(name)
          add_need_initialize_variable(name, 0)
        end

        def content=(content)
          if content.nil?
            @hour, @minute, @second, @content = nil
          else
            @hour, @minute, @second =
              ::RSS::ITunesItemModel::ITunesDuration.parse(content)
            @content = content
          end
        end

        def hour=(hour)
          @hour = Integer(hour)
          update_content
        end

        def minute=(minute)
          @minute = Integer(minute)
          update_content
        end

        def second=(second)
          @second = Integer(second)
          update_content
        end

        def to_feed(feed, current)
          if @content and current.respond_to?(:itunes_duration=)
            current.itunes_duration ||= current.class::ITunesDuration.new
            current.itunes_duration.content = @content
          end
        end

        private
        def update_content
          components = [@hour, @minute, @second]
          @content =
            ::RSS::ITunesItemModel::ITunesDuration.construct(*components)
        end
      end
    end

    class ChannelBase
      include Maker::ITunesChannelModel
      class ITunesCategories < ITunesCategoriesBase
        class ITunesCategory < ITunesCategoryBase
          ITunesCategory = self
        end
      end

      class ITunesImage < ITunesImageBase; end
      class ITunesOwner < ITunesOwnerBase; end
    end

    class ItemsBase
      class ItemBase
        include Maker::ITunesItemModel
        class ITunesDuration < ITunesDurationBase; end
        class ITunesImage < ITunesImageBase; end
      end
    end
  end
end
