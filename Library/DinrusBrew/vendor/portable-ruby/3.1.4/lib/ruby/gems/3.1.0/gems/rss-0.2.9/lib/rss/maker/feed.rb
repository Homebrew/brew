# frozen_string_literal: false
require_relative "atom"

module RSS
  module Maker
    module Atom
      class Feed < RSSBase
        def initialize(feed_version="1.0")
          super
          @feed_type = "atom"
          @feed_subtype = "feed"
        end

        private
        def make_feed
          ::RSS::Atom::Feed.new(@version, @encoding, @standalone)
        end

        def setup_elements(feed)
          setup_channel(feed)
          setup_image(feed)
          setup_items(feed)
        end

        class Channel < ChannelBase
          include SetupDefaultLanguage

          def to_feed(feed)
            set_default_values do
              setup_values(feed)
              feed.dc_dates.clear
              setup_other_elements(feed)
              if image_favicon.about
                icon = feed.class::Icon.new
                icon.content = image_favicon.about
                feed.icon = icon
              end
              unless have_required_values?
                raise NotSetError.new("maker.channel",
                                      not_set_required_variables)
              end
            end
          end

          def have_required_values?
            super and
              (!authors.empty? or
               @maker.items.any? {|item| !item.authors.empty?})
          end

          private
          def required_variable_names
            %w(id updated)
          end

          def variables
            super + %w(id updated)
          end

          def variable_is_set?
            super or !authors.empty?
          end

          def not_set_required_variables
            vars = super
            if authors.empty? and
                @maker.items.all? {|item| item.author.to_s.empty?}
              vars << "author"
            end
            vars << "title" unless title {|t| t.have_required_values?}
            vars
          end

          def _set_default_values(&block)
            keep = {
              :id => id,
            }
            self.id ||= about
            super(&block)
          ensure
            self.id = keep[:id]
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
            class Category < CategoryBase
              include AtomCategory

              def self.not_set_name
                "maker.channel.category"
              end
            end
          end

          class Links < LinksBase
            class Link < LinkBase
              include AtomLink

              def self.not_set_name
                "maker.channel.link"
              end
            end
          end

          AtomPersons.def_atom_persons(self, "author", "maker.channel.author")
          AtomPersons.def_atom_persons(self, "contributor",
                                       "maker.channel.contributor")

          class Generator < GeneratorBase
            include AtomGenerator

            def self.not_set_name
              "maker.channel.generator"
            end
          end

          AtomTextConstruct.def_atom_text_construct(self, "rights",
                                                    "maker.channel.copyright",
                                                    "Copyright")
          AtomTextConstruct.def_atom_text_construct(self, "subtitle",
                                                    "maker.channel.description",
                                                    "Description")
          AtomTextConstruct.def_atom_text_construct(self, "title",
                                                    "maker.channel.title")
        end

        class Image < ImageBase
          def to_feed(feed)
            logo = feed.class::Logo.new
            class << logo
              alias_method(:url=, :content=)
            end
            set = setup_values(logo)
            class << logo
              remove_method(:url=)
            end
            if set
              feed.logo = logo
              set_parent(logo, feed)
              setup_other_elements(feed, logo)
            elsif variable_is_set?
              raise NotSetError.new("maker.image", not_set_required_variables)
            end
          end

          private
          def required_variable_names
            %w(url)
          end
        end

        class Items < ItemsBase
          def to_feed(feed)
            normalize.each do |item|
              item.to_feed(feed)
            end
            setup_other_elements(feed, feed.entries)
          end

          class Item < ItemBase
            def to_feed(feed)
              set_default_values do
                entry = feed.class::Entry.new
                set = setup_values(entry)
                entry.dc_dates.clear
                setup_other_elements(feed, entry)
                if set
                  feed.entries << entry
                  set_parent(entry, feed)
                elsif variable_is_set?
                  raise NotSetError.new("maker.item", not_set_required_variables)
                end
              end
            end

            def have_required_values?
              set_default_values do
                super and title {|t| t.have_required_values?}
              end
            end

            private
            def required_variable_names
              %w(id updated)
            end

            def variables
              super + ["updated"]
            end

            def not_set_required_variables
              vars = super
              vars << "title" unless title {|t| t.have_required_values?}
              vars
            end

            def _set_default_values(&block)
              keep = {
                :id => id,
              }
              self.id ||= link
              super(&block)
            ensure
              self.id = keep[:id]
            end

            class Guid < GuidBase
              def to_feed(feed, current)
              end
            end

            class Enclosure < EnclosureBase
              def to_feed(feed, current)
              end
            end

            class Source < SourceBase
              def to_feed(feed, current)
                source = current.class::Source.new
                setup_values(source)
                current.source = source
                set_parent(source, current)
                setup_other_elements(feed, source)
                current.source = nil if source.to_s == "<source/>"
              end

              private
              def required_variable_names
                []
              end

              def variables
                super + ["updated"]
              end

              AtomPersons.def_atom_persons(self, "author",
                                           "maker.item.source.author")
              AtomPersons.def_atom_persons(self, "contributor",
                                           "maker.item.source.contributor")

              class Categories < CategoriesBase
                class Category < CategoryBase
                  include AtomCategory

                  def self.not_set_name
                    "maker.item.source.category"
                  end
                end
              end

              class Generator < GeneratorBase
                include AtomGenerator

                def self.not_set_name
                  "maker.item.source.generator"
                end
              end

              class Icon < IconBase
                def to_feed(feed, current)
                  icon = current.class::Icon.new
                  class << icon
                    alias_method(:url=, :content=)
                  end
                  set = setup_values(icon)
                  class << icon
                    remove_method(:url=)
                  end
                  if set
                    current.icon = icon
                    set_parent(icon, current)
                    setup_other_elements(feed, icon)
                  elsif variable_is_set?
                    raise NotSetError.new("maker.item.source.icon",
                                          not_set_required_variables)
                  end
                end

                private
                def required_variable_names
                  %w(url)
                end
              end

              class Links < LinksBase
                class Link < LinkBase
                  include AtomLink

                  def self.not_set_name
                    "maker.item.source.link"
                  end
                end
              end

              class Logo < LogoBase
                include AtomLogo

                def self.not_set_name
                  "maker.item.source.logo"
                end
              end

              maker_name_base = "maker.item.source."
              maker_name = "#{maker_name_base}rights"
              AtomTextConstruct.def_atom_text_construct(self, "rights",
                                                        maker_name)
              maker_name = "#{maker_name_base}subtitle"
              AtomTextConstruct.def_atom_text_construct(self, "subtitle",
                                                        maker_name)
              maker_name = "#{maker_name_base}title"
              AtomTextConstruct.def_atom_text_construct(self, "title",
                                                        maker_name)
            end

            class Categories < CategoriesBase
              class Category < CategoryBase
                include AtomCategory

                def self.not_set_name
                  "maker.item.category"
                end
              end
            end

            AtomPersons.def_atom_persons(self, "author", "maker.item.author")
            AtomPersons.def_atom_persons(self, "contributor",
                                         "maker.item.contributor")

            class Links < LinksBase
              class Link < LinkBase
                include AtomLink

                def self.not_set_name
                  "maker.item.link"
                end
              end
            end

            AtomTextConstruct.def_atom_text_construct(self, "rights",
                                                      "maker.item.rights")
            AtomTextConstruct.def_atom_text_construct(self, "summary",
                                                      "maker.item.description",
                                                      "Description")
            AtomTextConstruct.def_atom_text_construct(self, "title",
                                                      "maker.item.title")

            class Content < ContentBase
              def to_feed(feed, current)
                content = current.class::Content.new
                if setup_values(content)
                  content.src = nil if content.src and content.content
                  current.content = content
                  set_parent(content, current)
                  setup_other_elements(feed, content)
                elsif variable_is_set?
                  raise NotSetError.new("maker.item.content",
                                        not_set_required_variables)
                end
              end

              alias_method(:xml, :xml_content)

              private
              def required_variable_names
                if out_of_line?
                  %w(type)
                elsif xml_type?
                  %w(xml_content)
                else
                  %w(content)
                end
              end

              def variables
                if out_of_line?
                  super
                elsif xml_type?
                  super + %w(xml)
                else
                  super
                end
              end

              def xml_type?
                _type = type
                return false if _type.nil?
                _type == "xhtml" or
                  /(?:\+xml|\/xml)$/i =~ _type or
                  %w(text/xml-external-parsed-entity
                     application/xml-external-parsed-entity
                     application/xml-dtd).include?(_type.downcase)
              end
            end
          end
        end

        class Textinput < TextinputBase
        end
      end
    end

    add_maker("atom", "1.0", Atom::Feed)
    add_maker("atom:feed", "1.0", Atom::Feed)
    add_maker("atom1.0", "1.0", Atom::Feed)
    add_maker("atom1.0:feed", "1.0", Atom::Feed)
  end
end
