# frozen_string_literal: false
require_relative "../1.0"

require_relative "base"

module RSS
  module Maker

    class RSS10 < RSSBase

      def initialize(feed_version="1.0")
        super
        @feed_type = "rss"
      end

      private
      def make_feed
        RDF.new(@version, @encoding, @standalone)
      end

      def setup_elements(rss)
        setup_channel(rss)
        setup_image(rss)
        setup_items(rss)
        setup_textinput(rss)
      end

      class Channel < ChannelBase
        include SetupDefaultLanguage

        def to_feed(rss)
          set_default_values do
            _not_set_required_variables = not_set_required_variables
            if _not_set_required_variables.empty?
              channel = RDF::Channel.new(@about)
              setup_values(channel)
              channel.dc_dates.clear
              rss.channel = channel
              set_parent(channel, rss)
              setup_items(rss)
              setup_image(rss)
              setup_textinput(rss)
              setup_other_elements(rss, channel)
            else
              raise NotSetError.new("maker.channel", _not_set_required_variables)
            end
          end
        end

        private
        def setup_items(rss)
          items = RDF::Channel::Items.new
          seq = items.Seq
          set_parent(items, seq)
          target_items = @maker.items.normalize
          raise NotSetError.new("maker", ["items"]) if target_items.empty?
          target_items.each do |item|
            li = RDF::Channel::Items::Seq::Li.new(item.link)
            seq.lis << li
            set_parent(li, seq)
          end
          rss.channel.items = items
          set_parent(rss.channel, items)
        end

        def setup_image(rss)
          if @maker.image.have_required_values?
            image = RDF::Channel::Image.new(@maker.image.url)
            rss.channel.image = image
            set_parent(image, rss.channel)
          end
        end

        def setup_textinput(rss)
          if @maker.textinput.have_required_values?
            textinput = RDF::Channel::Textinput.new(@maker.textinput.link)
            rss.channel.textinput = textinput
            set_parent(textinput, rss.channel)
          end
        end

        def required_variable_names
          %w(about link)
        end

        def not_set_required_variables
          vars = super
          vars << "description" unless description {|d| d.have_required_values?}
          vars << "title" unless title {|t| t.have_required_values?}
          vars
        end

        class SkipDays < SkipDaysBase
          def to_feed(*args)
          end

          class Day < DayBase
          end
        end

        class SkipHours < SkipHoursBase
          def to_feed(*args)
          end

          class Hour < HourBase
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
          if @url
            image = RDF::Image.new(@url)
            set = setup_values(image)
            if set
              rss.image = image
              set_parent(image, rss)
              setup_other_elements(rss, image)
            end
          end
        end

        def have_required_values?
          super and @maker.channel.have_required_values?
        end

        private
        def variables
          super + ["link"]
        end

        def required_variable_names
          %w(url title link)
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
            set_default_values do
              item = RDF::Item.new(link)
              set = setup_values(item)
              if set
                item.dc_dates.clear
                rss.items << item
                set_parent(item, rss)
                setup_other_elements(rss, item)
              elsif !have_required_values?
                raise NotSetError.new("maker.item", not_set_required_variables)
              end
            end
          end

          private
          def required_variable_names
            %w(link)
          end

          def variables
            super + %w(link)
          end

          def not_set_required_variables
            set_default_values do
              vars = super
              vars << "title" unless title {|t| t.have_required_values?}
              vars
            end
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
            def to_feed(*args)
            end

            class Link < LinkBase
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
          if @link
            textinput = RDF::Textinput.new(@link)
            set = setup_values(textinput)
            if set
              rss.textinput = textinput
              set_parent(textinput, rss)
              setup_other_elements(rss, textinput)
            end
          end
        end

        def have_required_values?
          super and @maker.channel.have_required_values?
        end

        private
        def required_variable_names
          %w(title description name link)
        end
      end
    end

    add_maker("1.0", "1.0", RSS10)
    add_maker("rss1.0", "1.0", RSS10)
  end
end
