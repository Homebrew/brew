# frozen_string_literal: true
##
# Extracts message from RDoc::Store

class RDoc::Generator::POT::MessageExtractor

  ##
  # Creates a message extractor for +store+.

  def initialize store
    @store = store
    @po = RDoc::Generator::POT::PO.new
  end

  ##
  # Extracts messages from +store+, stores them into
  # RDoc::Generator::POT::PO and returns it.

  def extract
    @store.all_classes_and_modules.each do |klass|
      extract_from_klass(klass)
    end
    @po
  end

  private

  def extract_from_klass klass
    extract_text(klass.comment_location, klass.full_name)

    klass.each_section do |section, constants, attributes|
      extract_text(section.title ,"#{klass.full_name}: section title")
      section.comments.each do |comment|
        extract_text(comment, "#{klass.full_name}: #{section.title}")
      end
    end

    klass.each_constant do |constant|
      extract_text(constant.comment, constant.full_name)
    end

    klass.each_attribute do |attribute|
      extract_text(attribute.comment, attribute.full_name)
    end

    klass.each_method do |method|
      extract_text(method.comment, method.full_name)
    end
  end

  def extract_text text, comment, location = nil
    return if text.nil?

    options = {
      :extracted_comment => comment,
      :references => [location].compact,
    }
    i18n_text = RDoc::I18n::Text.new(text)
    i18n_text.extract_messages do |part|
      @po.add(entry(part[:paragraph], options))
    end
  end

  def entry msgid, options
    RDoc::Generator::POT::POEntry.new(msgid, options)
  end

end
