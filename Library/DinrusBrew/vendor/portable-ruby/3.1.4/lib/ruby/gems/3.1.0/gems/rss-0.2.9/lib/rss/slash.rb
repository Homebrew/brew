# frozen_string_literal: false
require 'rss/1.0'

module RSS
  # The prefix for the Slash XML namespace.
  SLASH_PREFIX = 'slash'
  # The URI of the Slash specification.
  SLASH_URI = "http://purl.org/rss/1.0/modules/slash/"

  RDF.install_ns(SLASH_PREFIX, SLASH_URI)

  module SlashModel
    extend BaseModel

    ELEMENT_INFOS = \
    [
     ["section"],
     ["department"],
     ["comments", :positive_integer],
     ["hit_parade", :csv_integer],
    ]

    class << self
      def append_features(klass)
        super

        return if klass.instance_of?(Module)
        klass.install_must_call_validator(SLASH_PREFIX, SLASH_URI)
        ELEMENT_INFOS.each do |name, type, *additional_infos|
          full_name = "#{SLASH_PREFIX}_#{name}"
          klass.install_text_element(full_name, SLASH_URI, "?",
                                     full_name, type, name)
        end

        klass.module_eval do
          alias_method(:slash_hit_parades, :slash_hit_parade)
          undef_method(:slash_hit_parade)
          alias_method(:slash_hit_parade, :slash_hit_parade_content)
        end
      end
    end
  end

  class RDF
    class Item; include SlashModel; end
  end

  SlashModel::ELEMENT_INFOS.each do |name, type|
    accessor_base = "#{SLASH_PREFIX}_#{name}"
    BaseListener.install_get_text_element(SLASH_URI, name, accessor_base)
  end
end
