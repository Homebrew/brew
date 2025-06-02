# frozen_string_literal: true
##
# Generates a POT file.
#
# Here is a translator work flow with the generator.
#
# == Create .pot
#
# You create .pot file by pot formatter:
#
#   % rdoc --format pot
#
# It generates doc/rdoc.pot.
#
# == Create .po
#
# You create .po file from doc/rdoc.pot. This operation is needed only
# the first time. This work flow assumes that you are a translator
# for Japanese.
#
# You create locale/ja/rdoc.po from doc/rdoc.pot. You can use msginit
# provided by GNU gettext or rmsginit provided by gettext gem. This
# work flow uses gettext gem because it is more portable than GNU
# gettext for Rubyists. Gettext gem is implemented by pure Ruby.
#
#   % gem install gettext
#   % mkdir -p locale/ja
#   % rmsginit --input doc/rdoc.pot --output locale/ja/rdoc.po --locale ja
#
# Translate messages in .po
#
# You translate messages in .po by a PO file editor. po-mode.el exists
# for Emacs users. There are some GUI tools such as GTranslator.
# There are some Web services such as POEditor and Tansifex. You can
# edit by your favorite text editor because .po is a text file.
# Generate localized documentation
#
# You can generate localized documentation with locale/ja/rdoc.po:
#
#   % rdoc --locale ja
#
# You can find documentation in Japanese in doc/. Yay!
#
# == Update translation
#
# You need to update translation when your application is added or
# modified messages.
#
# You can update .po by the following command lines:
#
#   % rdoc --format pot
#   % rmsgmerge --update locale/ja/rdoc.po doc/rdoc.pot
#
# You edit locale/ja/rdoc.po to translate new messages.

class RDoc::Generator::POT

  RDoc::RDoc.add_generator self

  ##
  # Description of this generator

  DESCRIPTION = 'creates .pot file'

  ##
  # Set up a new .pot generator

  def initialize store, options #:not-new:
    @options    = options
    @store      = store
  end

  ##
  # Writes .pot to disk.

  def generate
    po = extract_messages
    pot_path = 'rdoc.pot'
    File.open(pot_path, "w") do |pot|
      pot.print(po.to_s)
    end
  end

  # :nodoc:
  def class_dir
    nil
  end

  private
  def extract_messages
    extractor = MessageExtractor.new(@store)
    extractor.extract
  end

  require_relative 'pot/message_extractor'
  require_relative 'pot/po'
  require_relative 'pot/po_entry'

end
