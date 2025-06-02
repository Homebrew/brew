# frozen_string_literal: true
##
# Generates a PO format text

class RDoc::Generator::POT::PO

  ##
  # Creates an object that represents PO format.

  def initialize
    @entries = {}
    add_header
  end

  ##
  # Adds a PO entry to the PO.

  def add entry
    existing_entry = @entries[entry.msgid]
    if existing_entry
      entry = existing_entry.merge(entry)
    end
    @entries[entry.msgid] = entry
  end

  ##
  # Returns PO format text for the PO.

  def to_s
    po = ''
    sort_entries.each do |entry|
      po += "\n" unless po.empty?
      po += entry.to_s
    end
    po
  end

  private

  def add_header
    add(header_entry)
  end

  def header_entry
    comment = <<-COMMENT
SOME DESCRIPTIVE TITLE.
Copyright (C) YEAR THE PACKAGE'S COPYRIGHT HOLDER
This file is distributed under the same license as the PACKAGE package.
FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.
    COMMENT

    content = <<-CONTENT
Project-Id-Version: PACKAGE VERSEION
Report-Msgid-Bugs-To:
PO-Revision-Date: YEAR-MO_DA HO:MI+ZONE
Last-Translator: FULL NAME <EMAIL@ADDRESS>
Language-Team: LANGUAGE <LL@li.org>
Language:
MIME-Version: 1.0
Content-Type: text/plain; charset=CHARSET
Content-Transfer-Encoding: 8bit
Plural-Forms: nplurals=INTEGER; plural=EXPRESSION;
    CONTENT

    options = {
      :msgstr => content,
      :translator_comment => comment,
      :flags => ['fuzzy'],
    }
    RDoc::Generator::POT::POEntry.new('', options)
  end

  def sort_entries
    headers, messages = @entries.values.partition do |entry|
      entry.msgid.empty?
    end
    # TODO: sort by location
    sorted_messages = messages.sort_by do |entry|
      entry.msgid
    end
    headers + sorted_messages
  end

end
