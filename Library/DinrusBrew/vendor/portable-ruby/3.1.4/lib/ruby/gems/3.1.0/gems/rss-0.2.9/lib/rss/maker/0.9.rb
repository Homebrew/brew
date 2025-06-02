# frozen_string_literal: false
require_relative "../0.9"

require_relative "base"

module RSS
  module Maker

    class RSS09 < RSSBase

      def initialize(feed_version)
        super
        @feed_type = "rss"
      end

      private
      def make_feed
        Rss.new(@feed_version, @version, @encoding, @standalone)
      end

      def setup_elements(rss)
        setup_channel(rss)
      end

      class Channel < ChannelBase
        def to_feed(rss)
          channel = Rss::Channel.new
          setup_values(channel)
          _not_set_required_variables = not_set_required_variables
          if _not_set_required_variables.empty?
            rss.channel = channel
            set_parent(channel, rss)
            setup_items(rss)
            setup_image(rss)
            setup_textinput(rss)
            setup_other_elements(rss, channel)
            rss
          else
            raise NotSetError.new("maker.channel", _not_set_required_variables)
          end
        end

        private
        def setup_items(rss)
          @maker.items.to_feed(rss)
        end

        def setup_image(rss)
          @maker.image.to_feed(rss)
        end

        def setup_textinput(rss)
          @maker.textinput.to_feed(rss)
        end

        def variables
          super + ["pubDate"]
        end

        def required_variable_names
          %w(link language)
        end

        def not_set_required_variables
          vars = super
          vars << "description" unless description {|d| d.have_required_values?}
          vars << "title" unless title {|t| t.have_required_values?}
          vars
        end

        class SkipDays < SkipDaysBase
          def to_feed(rss, channel)
            unless @days.empty?
              skipDays = Rss::Channel::SkipDays.new
              channel.skipDays = skipDays
              set_parent(skipDays, channel)
              @days.each do |day|
                day.to_feed(rss, skipDays.days)
              end
            end
          end

          class Day < DayBase
            def to_feed(rss, days)
              day = Rss::Channel::SkipDays::Day.new
              set = setup_values(day)
              if set
                days << day
                set_parent(day, days)
                setup_other_elements(rss, day)
              end
            end

            private
            def required_variable_names
              %w(content)
            end
          end
        end

        class SkipHours < SkipHoursBase
          def to_feed(rss, channel)
            unless @hours.empty?
              skipHours = Rss::Channel::SkipHours.new
              channel.skipHours = skipHours
              set_parent(skipHours, channel)
              @hours.each do |hour|
                hour.to_feed(rss, skipHours.hours)
              end
            end
          end

          class Hour < HourBase
            def to_feed(rss, hours)
              hour = Rss::Channel::SkipHours::Hour.new
              set = setup_values(hour)
              if set
                hours << hour
                set_parent(hour, hours)
                setup_other_elements(rss, hour)
              end
            end

            private
            def required_variable_names
              %w(content)
            end
          end
        end

        class Cloud < CloudBase
          def to_feed(*args)
          end
        end

        class Categories < CategoriesBase
          def to_feed(*args)
          end

          class Category < CategoryBase
          end
        end

        class Links < LinksBase
          def to_feed(rss, channel)
            return if @links.empty?
            @links.first.to_feed(rss, channel)
          end

          class Link < LinkBase
            def to_feed(rss, channel)
              if have_required_values?
                channel.link = href
              else
                raise NotSetError.new("maker.channel.link",
                                      not_set_required_variables)
              end
            end

            private
            def required_variable_names
              %w(href)
            end
          end
        end

        class Authors < AuthorsBase
          def to_feed(rss, channel)
          end

          class Author < AuthorBase
            def to_feed(rss, channel)
            end
          end
        end

        class Contributors < ContributorsBase
          def to_feed(rss, channel)
          end

          class Contributor < ContributorBase
          end
        end

        class Generator < GeneratorBase
          def to_feed(rss, channel)
          end
        end

        class Copyright < CopyrightBase
          def to_feed(rss, channel)
            channel.copyright = content if have_required_values?
          end

          private
          def required_variable_names
            %w(content)
          end
        end

        class Description < DescriptionBase
          def to_feed(rss, channel)
            channel.description = content if have_required_values?
          end

          private
          def required_variable_names
            %w(content)
          end
        end

        class Title < TitleBase
          def to_feed(rss, channel)
            channel.title = content if have_required_values?
          end

          private
          def required_variable_names
            %w(content)
          end
        end
      end

      class Image < ImageBase
        def to_feed(rss)
          image = Rss::Channel::Image.new
          set = setup_values(image)
          if set
            image.link = link
            rss.channel.image = image
            set_parent(image, rss.channel)
            setup_other_elements(rss, image)
          elsif required_element?
            raise NotSetError.new("maker.image", not_set_required_variables)
          end
        end

        private
        def required_variable_names
          %w(url title link)
        end

        def required_element?
          true
        end
      end

      class Items < ItemsBase
        def to_feed(rss)
          if rss.channel
            normalize.each do |item|
              item.to_feed(rss)
            end
            setup_other_elements(rss, rss.items)
          end
        end

        class Item < ItemBase
          def to_feed(rss)
            item = Rss::Channel::Item.new
            setup_values(item)
            _not_set_required_variables = not_set_required_variables
            if _not_set_required_variables.empty?
              rss.items << item
              set_parent(item, rss.channel)
              setup_other_elements(rss, item)
            elsif variable_is_set?
              raise NotSetError.new("maker.items", _not_set_required_variables)
            end
          end

          private
          def required_variable_names
            []
          end

          def not_set_required_variables
            vars = super
            if @maker.feed_version == "0.91"
              vars << "title" unless title {|t| t.have_required_values?}
              vars << "link" unless link
            end
            vars
          end

          class Guid < GuidBase
            def to_feed(*args)
            end
          end

          class Enclosure < EnclosureBase
            def to_feed(*args)
            end
          end

          class Source < SourceBase
            def to_feed(*args)
            end

            class Authors < AuthorsBase
              def to_feed(*args)
              end

              class Author < AuthorBase
              end
            end

            class Categories < CategoriesBase
              def to_feed(*args)
              end

              class Category < CategoryBase
              end
            end

            class Contributors < ContributorsBase
              def to_feed(*args)
              end

              class Contributor < ContributorBase
              end
            end

            class Generator < GeneratorBase
              def to_feed(*args)
              end
            end

            class Icon < IconBase
              def to_feed(*args)
              end
            end

            class Links < LinksBase
              def to_feed(*args)
              end

              class Link < LinkBase
              end
            end

            class Logo < LogoBase
              def to_feed(*args)
              end
            end

            class Rights < RightsBase
              def to_feed(*args)
              end
            end

            class Subtitle < SubtitleBase
              def to_feed(*args)
              end
            end

            class Title < TitleBase
              def to_feed(*args)
              end
            end
          end

          class Categories < CategoriesBase
            def to_feed(*args)
            end

            class Category < CategoryBase
            end
          end

          class Authors < AuthorsBase
            def to_feed(*args)
            end

            class Author < AuthorBase
            end
          end

          class Links < LinksBase
            def to_feed(rss, item)
              return if @links.empty?
              @links.first.to_feed(rss, item)
            end

            class Link < LinkBase
              def to_feed(rss, item)
                if have_required_values?
                  item.link = href
                else
                  raise NotSetError.new("maker.link",
                                        not_set_required_variables)
                end
              end

              private
              def required_variable_names
                %w(href)
              end
            end
          end

          class Contributors < ContributorsBase
            def to_feed(rss, item)
            end

            class Contributor < ContributorBase
            end
          end

          class Rights < RightsBase
            def to_feed(rss, item)
            end
          end

          class Description < DescriptionBase
            def to_feed(rss, item)
              item.description = content if have_required_values?
            end

            private
            def required_variable_names
              %w(content)
            end
          end

          class Content < ContentBase
            def to_feed(rss, item)
            end
          end

          class Title < TitleBase
            def to_feed(rss, item)
              item.title = content if have_required_values?
            end

            private
            def required_variable_names
              %w(content)
            end
          end
        end
      end

      class Textinput < TextinputBase
        def to_feed(rss)
          textInput = Rss::Channel::TextInput.new
          set = setup_values(textInput)
          if set
            rss.channel.textInput = textInput
            set_parent(textInput, rss.channel)
            setup_other_elements(rss, textInput)
          end
        end

        private
        def required_variable_names
          %w(title description name link)
        end
      end
    end

    class RSS091 < RSS09
      def initialize(feed_version="0.91")
        super
      end

      class Channel < RSS09::Channel
      end

      class Items < RSS09::Items
        class Item < RSS09::Items::Item
        end
      end

      class Image < RSS09::Image
      end

      class Textinput < RSS09::Textinput
      end
    end

    class RSS092 < RSS09
      def initialize(feed_version="0.92")
        super
      end

      class Channel < RSS09::Channel
      end

      class Items < RSS09::Items
        class Item < RSS09::Items::Item
        end
      end

      class Image < RSS09::Image
      end

      class Textinput < RSS09::Textinput
      end
    end

    add_maker("0.9", "0.92", RSS092)
    add_maker("0.91", "0.91", RSS091)
    add_maker("0.92", "0.92", RSS092)
    add_maker("rss0.9", "0.92", RSS092)
    add_maker("rss0.91", "0.91", RSS091)
    add_maker("rss0.92", "0.92", RSS092)
  end
end
