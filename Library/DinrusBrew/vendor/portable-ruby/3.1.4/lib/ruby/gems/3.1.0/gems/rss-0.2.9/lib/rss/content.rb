# frozen_string_literal: false
require_relative "rss"

module RSS
  # The prefix for the Content XML namespace.
  CONTENT_PREFIX = 'content'
  # The URI of the Content specification.
  CONTENT_URI = "http://purl.org/rss/1.0/modules/content/"

  module ContentModel
    extend BaseModel

    ELEMENTS = ["#{CONTENT_PREFIX}_encoded"]

    def self.append_features(klass)
      super

      klass.install_must_call_validator(CONTENT_PREFIX, CONTENT_URI)
      ELEMENTS.each do |full_name|
        name = full_name[(CONTENT_PREFIX.size + 1)..-1]
        klass.install_text_element(name, CONTENT_URI, "?", full_name)
      end
    end
  end

  prefix_size = CONTENT_PREFIX.size + 1
  ContentModel::ELEMENTS.each do |full_name|
    name = full_name[prefix_size..-1]
    BaseListener.install_get_text_element(CONTENT_URI, name, full_name)
  end
end

require 'rss/content/1.0'
require 'rss/content/2.0'
