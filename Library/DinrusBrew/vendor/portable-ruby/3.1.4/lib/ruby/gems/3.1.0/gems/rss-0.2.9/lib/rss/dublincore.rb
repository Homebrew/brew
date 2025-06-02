# frozen_string_literal: false
require_relative "rss"

module RSS
  # The prefix for the Dublin Core XML namespace.
  DC_PREFIX = 'dc'
  # The URI of the Dublin Core specification.
  DC_URI = "http://purl.org/dc/elements/1.1/"

  module BaseDublinCoreModel
    def append_features(klass)
      super

      return if klass.instance_of?(Module)
      DublinCoreModel::ELEMENT_NAME_INFOS.each do |name, plural_name|
        plural = plural_name || "#{name}s"
        full_name = "#{DC_PREFIX}_#{name}"
        full_plural_name = "#{DC_PREFIX}_#{plural}"
        klass_name = "DublinCore#{Utils.to_class_name(name)}"
        klass.install_must_call_validator(DC_PREFIX, DC_URI)
        klass.install_have_children_element(name, DC_URI, "*",
                                            full_name, full_plural_name)
        klass.module_eval(<<-EOC, *get_file_and_line_from_caller(0))
          remove_method :#{full_name}
          remove_method :#{full_name}=
          remove_method :set_#{full_name}

          def #{full_name}
            @#{full_name}.first and @#{full_name}.first.value
          end

          def #{full_name}=(new_value)
            @#{full_name}[0] = Utils.new_with_value_if_need(#{klass_name}, new_value)
          end
          alias set_#{full_name} #{full_name}=
        EOC
      end
      klass.module_eval(<<-EOC, *get_file_and_line_from_caller(0))
        if method_defined?(:date)
          alias date_without_#{DC_PREFIX}_date= date=

          def date=(value)
            self.date_without_#{DC_PREFIX}_date = value
            self.#{DC_PREFIX}_date = value
          end
        else
          alias date #{DC_PREFIX}_date
          alias date= #{DC_PREFIX}_date=
        end

        # For backward compatibility
        alias #{DC_PREFIX}_rightses #{DC_PREFIX}_rights_list
      EOC
    end
  end

  module DublinCoreModel

    extend BaseModel
    extend BaseDublinCoreModel

    TEXT_ELEMENTS = {
      "title" => nil,
      "description" => nil,
      "creator" => nil,
      "subject" => nil,
      "publisher" => nil,
      "contributor" => nil,
      "type" => nil,
      "format" => nil,
      "identifier" => nil,
      "source" => nil,
      "language" => nil,
      "relation" => nil,
      "coverage" => nil,
      "rights" => "rights_list"
    }

    DATE_ELEMENTS = {
      "date" => "w3cdtf",
    }

    ELEMENT_NAME_INFOS = DublinCoreModel::TEXT_ELEMENTS.to_a
    DublinCoreModel::DATE_ELEMENTS.each do |name, |
      ELEMENT_NAME_INFOS << [name, nil]
    end

    ELEMENTS = TEXT_ELEMENTS.keys + DATE_ELEMENTS.keys

    ELEMENTS.each do |name, plural_name|
      module_eval(<<-EOC, *get_file_and_line_from_caller(0))
        class DublinCore#{Utils.to_class_name(name)} < Element
          include RSS10

          content_setup

          class << self
            def required_prefix
              DC_PREFIX
            end

            def required_uri
              DC_URI
            end
          end

          @tag_name = #{name.dump}

          alias_method(:value, :content)
          alias_method(:value=, :content=)

          def initialize(*args)
            if Utils.element_initialize_arguments?(args)
              super
            else
              super()
              self.content = args[0]
            end
          end

          def full_name
            tag_name_with_prefix(DC_PREFIX)
          end

          def maker_target(target)
            target.new_#{name}
          end

          def setup_maker_attributes(#{name})
            #{name}.content = content
          end
        end
      EOC
    end

    DATE_ELEMENTS.each do |name, type|
      tag_name = "#{DC_PREFIX}:#{name}"
      module_eval(<<-EOC, *get_file_and_line_from_caller(0))
        class DublinCore#{Utils.to_class_name(name)} < Element
          remove_method(:content=)
          remove_method(:value=)

          date_writer("content", #{type.dump}, #{tag_name.dump})

          alias_method(:value=, :content=)
        end
      EOC
    end
  end

  # For backward compatibility
  DublincoreModel = DublinCoreModel

  DublinCoreModel::ELEMENTS.each do |name|
    class_name = Utils.to_class_name(name)
    BaseListener.install_class_name(DC_URI, name, "DublinCore#{class_name}")
  end

  DublinCoreModel::ELEMENTS.collect! {|name| "#{DC_PREFIX}_#{name}"}
end

require 'rss/dublincore/1.0'
require 'rss/dublincore/2.0'
require_relative 'dublincore/atom'
