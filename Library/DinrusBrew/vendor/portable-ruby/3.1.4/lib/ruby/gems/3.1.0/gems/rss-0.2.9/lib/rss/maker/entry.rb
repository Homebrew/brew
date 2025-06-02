# frozen_string_literal: false
require_relative "atom"
require_relative "feed"

module RSS
  module Maker
    module Atom
      class Entry < RSSBase
        def initialize(feed_version="1.0")
          super
          @feed_type = "atom"
          @feed_subtype = "entry"
        end

        private
        def make_feed
          ::RSS::Atom::Entry.new(@version, @encoding, @standalone)
        end

        def setup_elements(entry)
          setup_items(entry)
        end

        class Channel < ChannelBase
          class SkipDays < SkipDaysBase
            class Day < DayBase
            end
          end

          class SkipHours < SkipHoursBase
            class Hour < HourBase
            end
          end

          class Cloud < CloudBase
          end

          Categories = Feed::Channel::Categories
          Links = Feed::Channel::Links
          Authors = Feed::Channel::Authors
          Contributors = Feed::Channel::Contributors

          class Generator < GeneratorBase
            include AtomGenerator

            def self.not_set_name
              "maker.channel.generator"
            end
          end

          Copyright = Feed::Channel::Copyright

          class Description < DescriptionBase
          end

          Title = Feed::Channel::Title
        end

        class Image < ImageBase
        end

        class Items < ItemsBase
          def to_feed(entry)
            (normalize.first || Item.new(@maker)).to_feed(entry)
          end

          class Item < ItemBase
            def to_feed(entry)
              set_default_values do
                setup_values(entry)
                entry.dc_dates.clear
                setup_other_elements(entry)
                unless have_required_values?
                  raise NotSetError.new("maker.item", not_set_required_variables)
                end
              end
            end

            private
            def required_variable_names
              %w(id updated)
            end

            def variables
              super + ["updated"]
            end

            def variable_is_set?
              super or !authors.empty?
            end

            def not_set_required_variables
              set_default_values do
                vars = super
                if authors.all? {|author| !author.have_required_values?}
                  vars << "author"
                end
                vars << "title" unless title {|t| t.have_required_values?}
                vars
              end
            end

            def _set_default_values
              keep = {
                :authors => authors.to_a.dup,
                :contributors => contributors.to_a.dup,
                :categories => categories.to_a.dup,
                :id => id,
                :links => links.to_a.dup,
                :rights => @rights,
                :title => @title,
                :updated => updated,
              }
              authors.replace(@maker.channel.authors) if keep[:authors].empty?
              if keep[:contributors].empty?
                contributors.replace(@maker.channel.contributors)
              end
              if keep[:categories].empty?
                categories.replace(@maker.channel.categories)
              end
              self.id ||= link || @maker.channel.id
              links.replace(@maker.channel.links) if keep[:links].empty?
              unless keep[:rights].variable_is_set?
                @maker.channel.rights {|r| @rights = r}
              end
              unless keep[:title].variable_is_set?
                @maker.channel.title {|t| @title = t}
              end
              self.updated ||= @maker.channel.updated
              super
            ensure
              authors.replace(keep[:authors])
              contributors.replace(keep[:contributors])
              categories.replace(keep[:categories])
              links.replace(keep[:links])
              self.id = keep[:id]
              @rights = keep[:rights]
              @title = keep[:title]
              self.updated = keep[:updated]
            end

            Guid = Feed::Items::Item::Guid
            Enclosure = Feed::Items::Item::Enclosure
            Source = Feed::Items::Item::Source
            Categories = Feed::Items::Item::Categories
            Authors = Feed::Items::Item::Authors
            Contributors = Feed::Items::Item::Contributors
            Links = Feed::Items::Item::Links
            Rights = Feed::Items::Item::Rights
            Description = Feed::Items::Item::Description
            Title = Feed::Items::Item::Title
            Content = Feed::Items::Item::Content
          end
        end

        class Textinput < TextinputBase
        end
      end
    end

    add_maker("atom:entry", "1.0", Atom::Entry)
    add_maker("atom1.0:entry", "1.0", Atom::Entry)
  end
end
