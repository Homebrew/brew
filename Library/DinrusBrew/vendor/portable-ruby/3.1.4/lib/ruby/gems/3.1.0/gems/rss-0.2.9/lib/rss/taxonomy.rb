# frozen_string_literal: false
require "rss/1.0"
require_relative "dublincore"

module RSS
  # The prefix for the Taxonomy XML namespace.
  TAXO_PREFIX = "taxo"
  # The URI for the specification of the Taxonomy XML namespace.
  TAXO_URI = "http://purl.org/rss/1.0/modules/taxonomy/"

  RDF.install_ns(TAXO_PREFIX, TAXO_URI)

  # The listing of all the taxonomy elements, with the appropriate namespace.
  TAXO_ELEMENTS = []

  %w(link).each do |name|
    full_name = "#{TAXO_PREFIX}_#{name}"
    BaseListener.install_get_text_element(TAXO_URI, name, full_name)
    TAXO_ELEMENTS << "#{TAXO_PREFIX}_#{name}"
  end

  %w(topic topics).each do |name|
    class_name = Utils.to_class_name(name)
    BaseListener.install_class_name(TAXO_URI, name, "Taxonomy#{class_name}")
    TAXO_ELEMENTS << "#{TAXO_PREFIX}_#{name}"
  end

  module TaxonomyTopicsModel
    extend BaseModel

    def self.append_features(klass)
      super

      klass.install_must_call_validator(TAXO_PREFIX, TAXO_URI)
      %w(topics).each do |name|
        klass.install_have_child_element(name, TAXO_URI, "?",
                                         "#{TAXO_PREFIX}_#{name}")
      end
    end

    class TaxonomyTopics < Element
      include RSS10

      Bag = ::RSS::RDF::Bag

      class << self
        def required_prefix
          TAXO_PREFIX
        end

        def required_uri
          TAXO_URI
        end
      end

      @tag_name = "topics"

      install_have_child_element("Bag", RDF::URI, nil)
      install_must_call_validator('rdf', RDF::URI)

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.Bag = args[0]
        end
        self.Bag ||= Bag.new
      end

      def full_name
        tag_name_with_prefix(TAXO_PREFIX)
      end

      def maker_target(target)
        target.taxo_topics
      end

      def resources
        if @Bag
          @Bag.lis.collect do |li|
            li.resource
          end
        else
          []
        end
      end
    end
  end

  module TaxonomyTopicModel
    extend BaseModel

    def self.append_features(klass)
      super
      var_name = "#{TAXO_PREFIX}_topic"
      klass.install_have_children_element("topic", TAXO_URI, "*", var_name)
    end

    class TaxonomyTopic < Element
      include RSS10

      include DublinCoreModel
      include TaxonomyTopicsModel

      class << self
        def required_prefix
          TAXO_PREFIX
        end

        def required_uri
          TAXO_URI
        end
      end

      @tag_name = "topic"

      install_get_attribute("about", ::RSS::RDF::URI, true, nil, nil,
                            "#{RDF::PREFIX}:about")
      install_text_element("link", TAXO_URI, "?", "#{TAXO_PREFIX}_link")

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.about = args[0]
        end
      end

      def full_name
        tag_name_with_prefix(TAXO_PREFIX)
      end

      def maker_target(target)
        target.new_taxo_topic
      end
    end
  end

  class RDF
    include TaxonomyTopicModel
    class Channel
      include TaxonomyTopicsModel
    end
    class Item; include TaxonomyTopicsModel; end
  end
end
