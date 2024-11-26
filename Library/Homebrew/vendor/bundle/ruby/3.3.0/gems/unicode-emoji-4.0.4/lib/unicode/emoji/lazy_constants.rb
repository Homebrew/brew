# frozen_string_literal: true

module Unicode
  module Emoji
    # The current list of codepoints with the "Emoji" property
    # Same characters as \p{Emoji}
    # (Emoji version of this gem might be more recent than Ruby's Emoji version)
    EMOJI_CHAR                    = INDEX[:PROPERTIES].select{ |ord, props| props.include?(:E) }.keys.freeze

    # The current list of codepoints with the "Emoji_Presentation" property
    # Same characters as \p{Emoji Presentation} or \p{EPres}
    # (Emoji version of this gem might be more recent than Ruby's Emoji version)
    EMOJI_PRESENTATION            = INDEX[:PROPERTIES].select{ |ord, props| props.include?(:P) }.keys.freeze

    # The current list of codepoints with the "Emoji" property that lack the "Emoji Presentation" property
    TEXT_PRESENTATION             = INDEX[:PROPERTIES].select{ |ord, props| props.include?(:E) && !props.include?(:P) }.keys.freeze

    # The current list of codepoints with the "Emoji_Component" property
    # Same characters as \p{Emoji Component} or \p{EComp}
    # (Emoji version of this gem might be more recent than Ruby's Emoji version)
    EMOJI_COMPONENT               = INDEX[:PROPERTIES].select{ |ord, props| props.include?(:C) }.keys.freeze

    # The current list of codepoints with the "Emoji_Modifier_Base" property
    # Same characters as \p{Emoji Modifier Base} or \p{EBase}
    # (Emoji version of this gem might be more recent than Ruby's Emoji version)
    EMOJI_MODIFIER_BASES          = INDEX[:PROPERTIES].select{ |ord, props| props.include?(:B) }.keys.freeze

    # The current list of codepoints with the "Emoji_Modifier" property
    # Same characters as \p{Emoji Modifier} or \p{EMod}
    # (Emoji version of this gem might be more recent than Ruby's Emoji version)
    EMOJI_MODIFIERS               = INDEX[:PROPERTIES].select{ |ord, props| props.include?(:M) }.keys.freeze

    # The current list of codepoints with the "Extended_Pictographic" property
    # Same characters as \p{Extended Pictographic} or \p{ExtPict}
    # (Emoji version of this gem might be more recent than Ruby's Emoji version)
    EXTENDED_PICTOGRAPHIC         = INDEX[:PROPERTIES].select{ |ord, props| props.include?(:X) }.keys.freeze

    # The current list of codepoints with the "Extended_Pictographic" property that don't have the "Emoji" property
    EXTENDED_PICTOGRAPHIC_NO_EMOJI= INDEX[:PROPERTIES].select{ |ord, props| props.include?(:X) && !props.include?(:E) }.keys.freeze

    # The list of characters that can be used as base for keycap sequences
    EMOJI_KEYCAPS                 = INDEX[:KEYCAPS].freeze

    # The list of valid regions
    VALID_REGION_FLAGS            = INDEX[:FLAGS].freeze

    # The list of valid subdivisions in regex character class syntax
    VALID_SUBDIVISIONS            = INDEX[:SD].map{_1.sub(/(.)~(.)/, '[\1-\2]') }

    # The list RGI tag sequence flags
    RECOMMENDED_SUBDIVISION_FLAGS = INDEX[:TAGS].freeze

    # The list of fully-qualified RGI Emoji ZWJ sequences
    RECOMMENDED_ZWJ_SEQUENCES     = INDEX[:ZWJ].freeze
  end
end
