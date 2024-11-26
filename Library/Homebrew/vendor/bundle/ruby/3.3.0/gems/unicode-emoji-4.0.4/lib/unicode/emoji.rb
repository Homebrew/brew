# frozen_string_literal: true

require_relative "emoji/constants"

module Unicode
  module Emoji
    autoload :INDEX, File.expand_path('emoji/index', __dir__)

    %w[
      EMOJI_CHAR
      EMOJI_PRESENTATION
      TEXT_PRESENTATION
      EMOJI_COMPONENT
      EMOJI_MODIFIER_BASES
      EMOJI_MODIFIERS
      EXTENDED_PICTOGRAPHIC
      EXTENDED_PICTOGRAPHIC_NO_EMOJI
      EMOJI_KEYCAPS
      VALID_REGION_FLAGS
      VALID_SUBDIVISIONS
      RECOMMENDED_SUBDIVISION_FLAGS
      RECOMMENDED_ZWJ_SEQUENCES
    ].each do |const_name|
      autoload const_name, File.expand_path('emoji/lazy_constants', __dir__)
    end

    %w[
      LIST
      LIST_REMOVED_KEYS
    ].each do |const_name|
      autoload const_name, File.expand_path('emoji/list', __dir__)
    end

    generated_constants_dirpath = File.expand_path(
      EMOJI_VERSION == RbConfig::CONFIG["UNICODE_EMOJI_VERSION"] ? "emoji/generated_native/" : "emoji/generated/",
      __dir__
    )

    %w[
      REGEX
      REGEX_INCLUDE_TEXT
      REGEX_INCLUDE_MQE
      REGEX_INCLUDE_MQE_UQE
      REGEX_VALID
      REGEX_VALID_INCLUDE_TEXT
      REGEX_WELL_FORMED
      REGEX_WELL_FORMED_INCLUDE_TEXT
      REGEX_POSSIBLE
      REGEX_BASIC
      REGEX_TEXT
      REGEX_TEXT_PRESENTATION
      REGEX_PROP_EMOJI
      REGEX_PROP_MODIFIER
      REGEX_PROP_MODIFIER_BASE
      REGEX_PROP_COMPONENT
      REGEX_PROP_PRESENTATION
      REGEX_PICTO
      REGEX_PICTO_NO_EMOJI
      REGEX_EMOJI_KEYCAP
    ].each do |const_name|
      autoload const_name, File.join(generated_constants_dirpath, const_name.downcase)
    end

    # Return Emoji properties of character as an Array or nil
    # See PROPERTY_NAMES constant for possible properties
    # 
    # Source: see https://www.unicode.org/Public/16.0.0/ucd/emoji/emoji-data.txt
    def self.properties(char)
      ord = get_codepoint_value(char)
      props = INDEX[:PROPERTIES][ord]

      if props
        props.map{ |prop| PROPERTY_NAMES[prop] }
      else
        # nothing
      end
    end

    # Returns ordered list of Emoji, categorized in a three-level deep Hash structure
    def self.list(key = nil, sub_key = nil)
      return LIST unless key || sub_key
      if LIST_REMOVED_KEYS.include?(key)
        $stderr.puts "Warning(unicode-emoji): The category of #{key} does not exist anymore"
      end
      LIST.dig(*[key, sub_key].compact)
    end

    def self.get_codepoint_value(char)
      ord = nil

      if char.valid_encoding?
        ord = char.ord
      elsif char.encoding.name == "UTF-8"
        begin
          ord = char.unpack("U*")[0]
        rescue ArgumentError
        end
      end

      if ord
        ord
      else
        raise(ArgumentError, "Unicode::Emoji must be given a valid string")
      end
    end

    class << self
      private :get_codepoint_value
    end
  end
end
