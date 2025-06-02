# frozen_string_literal: false
require "rss/0.9"

module RSS

  ##
  # = RSS 2.0 support
  #
  # RSS has three different versions. This module contains support for version
  # 2.0[http://www.rssboard.org/rss-specification]
  #
  # == Producing RSS 2.0
  #
  # Producing our own RSS feeds is easy as well. Let's make a very basic feed:
  #
  #  require "rss"
  #
  #  rss = RSS::Maker.make("2.0") do |maker|
  #    maker.channel.language = "en"
  #    maker.channel.author = "matz"
  #    maker.channel.updated = Time.now.to_s
  #    maker.channel.link = "http://www.ruby-lang.org/en/feeds/news.rss"
  #    maker.channel.title = "Example Feed"
  #    maker.channel.description = "A longer description of my feed."
  #    maker.items.new_item do |item|
  #      item.link = "http://www.ruby-lang.org/en/news/2010/12/25/ruby-1-9-2-p136-is-released/"
  #      item.title = "Ruby 1.9.2-p136 is released"
  #      item.updated = Time.now.to_s
  #    end
  #  end
  #
  #  puts rss
  #
  # As you can see, this is a very Builder-like DSL. This code will spit out an
  # RSS 2.0 feed with one item. If we needed a second item, we'd make another
  # block with maker.items.new_item and build a second one.
  class Rss

    class Channel

      [
        ["generator"],
        ["ttl", :integer],
      ].each do |name, type|
        install_text_element(name, "", "?", name, type)
      end

      [
        %w(category categories),
      ].each do |name, plural_name|
        install_have_children_element(name, "", "*", name, plural_name)
      end

      [
        ["image", "?"],
        ["language", "?"],
      ].each do |name, occurs|
        install_model(name, "", occurs)
      end

      Category = Item::Category

      class Item

        [
          ["comments", "?"],
          ["author", "?"],
        ].each do |name, occurs|
          install_text_element(name, "", occurs)
        end

        [
          ["pubDate", '?'],
        ].each do |name, occurs|
          install_date_element(name, "", occurs, name, 'rfc822')
        end
        alias date pubDate
        alias date= pubDate=

        [
          ["guid", '?'],
        ].each do |name, occurs|
          install_have_child_element(name, "", occurs)
        end

        private
        alias _setup_maker_element setup_maker_element
        def setup_maker_element(item)
          _setup_maker_element(item)
          @guid.setup_maker(item) if @guid
        end

        class Guid < Element

          include RSS09

          [
            ["isPermaLink", "", false, :boolean]
          ].each do |name, uri, required, type|
            install_get_attribute(name, uri, required, type)
          end

          content_setup

          def initialize(*args)
            if Utils.element_initialize_arguments?(args)
              super
            else
              super()
              self.isPermaLink = args[0]
              self.content = args[1]
            end
          end

          alias_method :_PermaLink?, :PermaLink?
          private :_PermaLink?
          def PermaLink?
            perma = _PermaLink?
            perma or perma.nil?
          end

          private
          def maker_target(item)
            item.guid
          end

          def setup_maker_attributes(guid)
            guid.isPermaLink = isPermaLink
            guid.content = content
          end
        end

      end

    end

  end

  RSS09::ELEMENTS.each do |name|
    BaseListener.install_get_text_element("", name, name)
  end

end
