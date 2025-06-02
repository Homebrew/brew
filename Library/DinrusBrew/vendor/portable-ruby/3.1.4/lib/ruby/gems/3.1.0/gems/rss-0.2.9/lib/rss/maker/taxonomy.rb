# frozen_string_literal: false
require_relative '../taxonomy'
require_relative '1.0'
require_relative 'dublincore'

module RSS
  module Maker
    module TaxonomyTopicsModel
      def self.append_features(klass)
        super

        klass.def_classed_element("#{RSS::TAXO_PREFIX}_topics",
                                  "TaxonomyTopics")
      end

      def self.install_taxo_topics(klass)
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          class TaxonomyTopics < TaxonomyTopicsBase
            def to_feed(feed, current)
              if current.respond_to?(:taxo_topics)
                topics = current.class::TaxonomyTopics.new
                bag = topics.Bag
                @resources.each do |resource|
                  bag.lis << RDF::Bag::Li.new(resource)
                end
                current.taxo_topics = topics
              end
            end
          end
EOC
      end

      class TaxonomyTopicsBase < Base
        attr_reader :resources
        def_array_element("resource")
        remove_method :new_resource
      end
    end

    module TaxonomyTopicModel
      def self.append_features(klass)
        super

        class_name = "TaxonomyTopics"
        klass.def_classed_elements("#{TAXO_PREFIX}_topic", "value", class_name)
      end

      def self.install_taxo_topic(klass)
        klass.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          class TaxonomyTopics < TaxonomyTopicsBase
            class TaxonomyTopic < TaxonomyTopicBase
              DublinCoreModel.install_dublin_core(self)
              TaxonomyTopicsModel.install_taxo_topics(self)

              def to_feed(feed, current)
                if current.respond_to?(:taxo_topics)
                  topic = current.class::TaxonomyTopic.new(value)
                  topic.taxo_link = value
                  taxo_topics.to_feed(feed, topic) if taxo_topics
                  current.taxo_topics << topic
                  setup_other_elements(feed, topic)
                end
              end
            end
          end
EOC
      end

      class TaxonomyTopicsBase < Base
        def_array_element("topic", nil, "TaxonomyTopic")
        alias_method(:new_taxo_topic, :new_topic) # For backward compatibility

        class TaxonomyTopicBase < Base
          include DublinCoreModel
          include TaxonomyTopicsModel

          attr_accessor :value
          add_need_initialize_variable("value")
          alias_method(:taxo_link, :value)
          alias_method(:taxo_link=, :value=)

          def have_required_values?
            @value
          end
        end
      end
    end

    class RSSBase
      include TaxonomyTopicModel
    end

    class ChannelBase
      include TaxonomyTopicsModel
    end

    class ItemsBase
      class ItemBase
        include TaxonomyTopicsModel
      end
    end

    makers.each do |maker|
      maker.module_eval(<<-EOC, __FILE__, __LINE__ + 1)
        TaxonomyTopicModel.install_taxo_topic(self)

        class Channel
          TaxonomyTopicsModel.install_taxo_topics(self)
        end

        class Items
          class Item
            TaxonomyTopicsModel.install_taxo_topics(self)
          end
        end
      EOC
    end
  end
end
