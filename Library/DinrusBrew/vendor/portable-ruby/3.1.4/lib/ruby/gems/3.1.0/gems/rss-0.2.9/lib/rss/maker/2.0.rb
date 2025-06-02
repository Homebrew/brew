# frozen_string_literal: false
require_relative "../2.0"

require_relative "0.9"

module RSS
  module Maker

    class RSS20 < RSS09

      def initialize(feed_version="2.0")
        super
      end

      class Channel < RSS09::Channel

        private
        def required_variable_names
          %w(link)
        end

        class SkipDays < RSS09::Channel::SkipDays
          class Day < RSS09::Channel::SkipDays::Day
          end
        end

        class SkipHours < RSS09::Channel::SkipHours
          class Hour < RSS09::Channel::SkipHours::Hour
          end
        end

        class Cloud < RSS09::Channel::Cloud
          def to_feed(rss, channel)
            cloud = Rss::Channel::Cloud.new
            set = setup_values(cloud)
            if set
              channel.cloud = cloud
              set_parent(cloud, channel)
              setup_other_elements(rss, cloud)
            end
          end

          private
          def required_variable_names
            %w(domain port path registerProcedure protocol)
          end
        end

        class Categories < RSS09::Channel::Categories
          def to_feed(rss, channel)
            @categories.each do |category|
              category.to_feed(rss, channel)
            end
          end

          class Category < RSS09::Channel::Categories::Category
            def to_feed(rss, channel)
              category = Rss::Channel::Category.new
              set = setup_values(category)
              if set
                channel.categories << category
                set_parent(category, channel)
                setup_other_elements(rss, category)
              end
            end

            private
            def required_variable_names
              %w(content)
            end
          end
        end

        class Generator < GeneratorBase
          def to_feed(rss, channel)
            channel.generator = content
          end

          private
          def required_variable_names
            %w(content)
          end
        end
      end

      class Image < RSS09::Image
        private
        def required_element?
          false
        end
      end

      class Items < RSS09::Items
        class Item < RSS09::Items::Item
          private
          def required_variable_names
            []
          end

          def not_set_required_variables
            vars = super
            if !title {|t| t.have_required_values?} and
                !description {|d| d.have_required_values?}
              vars << "title or description"
            end
            vars
          end

          def variables
            super + ["pubDate"]
          end

          class Guid < RSS09::Items::Item::Guid
            def to_feed(rss, item)
              guid = Rss::Channel::Item::Guid.new
              set = setup_values(guid)
              if set
                item.guid = guid
                set_parent(guid, item)
                setup_other_elements(rss, guid)
              end
            end

            private
            def required_variable_names
              %w(content)
            end
          end

          class Enclosure < RSS09::Items::Item::Enclosure
            def to_feed(rss, item)
              enclosure = Rss::Channel::Item::Enclosure.new
              set = setup_values(enclosure)
              if set
                item.enclosure = enclosure
                set_parent(enclosure, item)
                setup_other_elements(rss, enclosure)
              end
            end

            private
            def required_variable_names
              %w(url length type)
            end
          end

          class Source < RSS09::Items::Item::Source
            def to_feed(rss, item)
              source = Rss::Channel::Item::Source.new
              set = setup_values(source)
              if set
                item.source = source
                set_parent(source, item)
                setup_other_elements(rss, source)
              end
            end

            private
            def required_variable_names
              %w(url content)
            end

            class Links < RSS09::Items::Item::Source::Links
              def to_feed(rss, source)
                return if @links.empty?
                @links.first.to_feed(rss, source)
              end

              class Link < RSS09::Items::Item::Source::Links::Link
                def to_feed(rss, source)
                  source.url = href
                end
              end
            end
          end

          class Categories < RSS09::Items::Item::Categories
            def to_feed(rss, item)
              @categories.each do |category|
                category.to_feed(rss, item)
              end
            end

            class Category < RSS09::Items::Item::Categories::Category
              def to_feed(rss, item)
                category = Rss::Channel::Item::Category.new
                set = setup_values(category)
                if set
                  item.categories << category
                  set_parent(category, item)
                  setup_other_elements(rss)
                end
              end

              private
              def required_variable_names
                %w(content)
              end
            end
          end

          class Authors < RSS09::Items::Item::Authors
            def to_feed(rss, item)
              return if @authors.empty?
              @authors.first.to_feed(rss, item)
            end

            class Author < RSS09::Items::Item::Authors::Author
              def to_feed(rss, item)
                item.author = name
              end
            end
          end
        end
      end

      class Textinput < RSS09::Textinput
      end
    end

    add_maker("2.0", "2.0", RSS20)
    add_maker("rss2.0", "2.0", RSS20)
  end
end
