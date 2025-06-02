# frozen_string_literal: true
##
# A message container for a locale.
#
# This object provides the following two features:
#
#   * Loads translated messages from .po file.
#   * Translates a message into the locale.

class RDoc::I18n::Locale

  @@locales = {} # :nodoc:

  class << self

    ##
    # Returns the locale object for +locale_name+.

    def [](locale_name)
      @@locales[locale_name] ||= new(locale_name)
    end

    ##
    # Sets the locale object for +locale_name+.
    #
    # Normally, this method is not used. This method is useful for
    # testing.

    def []=(locale_name, locale)
      @@locales[locale_name] = locale
    end

  end

  ##
  # The name of the locale. It uses IETF language tag format
  # +[language[_territory][.codeset][@modifier]]+.
  #
  # See also {BCP 47 - Tags for Identifying
  # Languages}[http://tools.ietf.org/rfc/bcp/bcp47.txt].

  attr_reader :name

  ##
  # Creates a new locale object for +name+ locale. +name+ must
  # follow IETF language tag format.

  def initialize(name)
    @name = name
    @messages = {}
  end

  ##
  # Loads translation messages from +locale_directory+/+@name+/rdoc.po
  # or +locale_directory+/+@name+.po. The former has high priority.
  #
  # This method requires gettext gem for parsing .po file. If you
  # don't have gettext gem, this method doesn't load .po file. This
  # method warns and returns +false+.
  #
  # Returns +true+ if succeeded, +false+ otherwise.

  def load(locale_directory)
    return false if @name.nil?

    po_file_candidates = [
      File.join(locale_directory, @name, 'rdoc.po'),
      File.join(locale_directory, "#{@name}.po"),
    ]
    po_file = po_file_candidates.find do |po_file_candidate|
      File.exist?(po_file_candidate)
    end
    return false unless po_file

    begin
      require 'gettext/po_parser'
      require 'gettext/mo'
    rescue LoadError
      warn('Need gettext gem for i18n feature:')
      warn('  gem install gettext')
      return false
    end

    po_parser = GetText::POParser.new
    messages = GetText::MO.new
    po_parser.report_warning = false
    po_parser.parse_file(po_file, messages)

    @messages.merge!(messages)

    true
  end

  ##
  # Translates the +message+ into locale. If there is no translation
  # messages for +message+ in locale, +message+ itself is returned.

  def translate(message)
    @messages[message] || message
  end

end
