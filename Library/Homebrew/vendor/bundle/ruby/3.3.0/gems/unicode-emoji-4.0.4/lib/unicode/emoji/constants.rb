# frozen_string_literal: true

module Unicode
  module Emoji
    VERSION = "4.0.4"
    EMOJI_VERSION = "16.0"
    CLDR_VERSION = "46"
    DATA_DIRECTORY = File.expand_path('../../../data', __dir__).freeze
    INDEX_FILENAME = (DATA_DIRECTORY + "/emoji.marshal.gz").freeze

    # Unicode properties, see https://www.unicode.org/Public/16.0.0/ucd/emoji/emoji-data.txt
    PROPERTY_NAMES = {
      E: "Emoji",
      B: "Emoji_Modifier_Base",
      M: "Emoji_Modifier",
      C: "Emoji_Component",
      P: "Emoji_Presentation",
      X: "Extended_Pictographic",
    }.freeze

    # Variation Selector 16 (VS16), enables emoji presentation mode for preceding codepoint
    EMOJI_VARIATION_SELECTOR      = 0xFE0F

    # Variation Selector 15 (VS15), enables text presentation mode for preceding codepoint
    TEXT_VARIATION_SELECTOR       = 0xFE0E

    # First codepoint of tag-based subdivision flags
    EMOJI_TAG_BASE_FLAG           = 0x1F3F4

    # Last codepoint of tag-based subdivision flags
    CANCEL_TAG                    = 0xE007F

    # Tags characters allowed in tag-based subdivision flags
    SPEC_TAGS                     = [*0xE0030..0xE0039, *0xE0061..0xE007A].freeze

    # Combining Enclosing Keycap character
    EMOJI_KEYCAP_SUFFIX           = 0x20E3

    # Zero-width-joiner to enable combination of multiple Emoji in a sequence
    ZWJ                           = 0x200D

    # Two regional indicators make up a region
    REGIONAL_INDICATORS           = [*0x1F1E6..0x1F1FF].freeze

    # The current list of Emoji components that should have a visual representation
    # Currently skin tone modifiers + hair components
    VISUAL_COMPONENT              = [*0x1F3FB..0x1F3FF, *0x1F9B0..0x1F9B3].freeze
  end
end
