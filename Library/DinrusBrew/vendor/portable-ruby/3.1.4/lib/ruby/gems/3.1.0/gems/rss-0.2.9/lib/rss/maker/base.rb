# frozen_string_literal: false
require 'forwardable'

require_relative '../rss'

module RSS
  module Maker
    class Base
      extend Utils::InheritedReader

      OTHER_ELEMENTS = []
      NEED_INITIALIZE_VARIABLES = []

      class << self
        def other_elements
          inherited_array_reader("OTHER_ELEMENTS")
        end
        def need_initialize_variables
          inherited_array_reader("NEED_INITIALIZE_VARIABLES")
        end

        def inherited_base
          ::RSS::Maker::Base
        end

        def inherited(subclass)
          subclass.const_set(:OTHER_ELEMENTS, [])
          subclass.const_set(:NEED_INITIALIZE_VARIABLES, [])
        end

        def add_other_element(variable_name)
          self::OTHER_ELEMENTS << variable_name
        end

        def add_need_initialize_variable(variable_name, init_value=nil,
                                         &init_block)
          init_value ||= init_block
          self::NEED_INITIALIZE_VARIABLES << [variable_name, init_value]
        end

        def def_array_element(name, plural=nil, klass_name=nil)
          include Enumerable
          extend Forwardable

          plural ||= "#{name}s"
          klass_name ||= Utils.to_class_name(name)
          def_delegators("@#{plural}", :<<, :[], :[]=, :first, :last)
          def_delegators("@#{plural}", :push, :pop, :shift, :unshift)
          def_delegators("@#{plural}", :each, :size, :empty?, :clear)

          add_need_initialize_variable(plural) {[]}

          module_eval(<<-EOC, __FILE__, __LINE__ + 1)
            def new_#{name}
              #{name} = self.class::#{klass_name}.new(@maker)
              @#{plural} << #{name}
              if block_given?
                yield #{name}
              else
                #{name}
              end
            end
            alias new_child new_#{name}

            def to_feed(*args)
              @#{plural}.each do |#{name}|
                #{name}.to_feed(*args)
              end
            end

            def replace(elements)
              @#{plural}.replace(elements.to_a)
            end
          EOC
        end

        def def_classed_element_without_accessor(name, class_name=nil)
          class_name ||= Utils.to_class_name(name)
          add_other_element(name)
          add_need_initialize_variable(name) do |object|
            object.send("make_#{name}")
          end
          module_eval(<<-EOC, __FILE__, __LINE__ + 1)
            private
            def setup_#{name}(feed, current)
              @#{name}.to_feed(feed, current)
            end

            def make_#{name}
              self.class::#{class_name}.new(@maker)
            end
          EOC
        end

        def def_classed_element(name, class_name=nil, attribute_name=nil)
          def_classed_element_without_accessor(name, class_name)
          if attribute_name
            module_eval(<<-EOC, __FILE__, __LINE__ + 1)
              def #{name}
                if block_given?
                  yield(@#{name})
                else
                  @#{name}.#{attribute_name}
                end
              end

              def #{name}=(new_value)
                @#{name}.#{attribute_name} = new_value
              end
            EOC
          else
            attr_reader name
          end
        end

        def def_classed_elements(name, attribute, plural_class_name=nil,
                                 plural_name=nil, new_name=nil)
          plural_name ||= "#{name}s"
          new_name ||= name
          def_classed_element(plural_name, plural_class_name)
          local_variable_name = "_#{name}"
          new_value_variable_name = "new_value"
          additional_setup_code = nil
          if block_given?
            additional_setup_code = yield(local_variable_name,
                                          new_value_variable_name)
          end
          module_eval(<<-EOC, __FILE__, __LINE__ + 1)
            def #{name}
              #{local_variable_name} = #{plural_name}.first
              #{local_variable_name} ? #{local_variable_name}.#{attribute} : nil
            end

            def #{name}=(#{new_value_variable_name})
              #{local_variable_name} =
                #{plural_name}.first || #{plural_name}.new_#{new_name}
              #{additional_setup_code}
              #{local_variable_name}.#{attribute} = #{new_value_variable_name}
            end
          EOC
        end

        def def_other_element(name)
          attr_accessor name
          def_other_element_without_accessor(name)
        end

        def def_other_element_without_accessor(name)
          add_need_initialize_variable(name)
          add_other_element(name)
          module_eval(<<-EOC, __FILE__, __LINE__ + 1)
            def setup_#{name}(feed, current)
              if !@#{name}.nil? and current.respond_to?(:#{name}=)
                current.#{name} = @#{name}
              end
            end
          EOC
        end

        def def_csv_element(name, type=nil)
          def_other_element_without_accessor(name)
          attr_reader(name)
          converter = ""
          if type == :integer
            converter = "{|v| Integer(v)}"
          end
          module_eval(<<-EOC, __FILE__, __LINE__ + 1)
            def #{name}=(value)
              @#{name} = Utils::CSV.parse(value)#{converter}
            end
          EOC
        end
      end

      attr_reader :maker
      def initialize(maker)
        @maker = maker
        @default_values_are_set = false
        initialize_variables
      end

      def have_required_values?
        not_set_required_variables.empty?
      end

      def variable_is_set?
        variables.any? {|var| not __send__(var).nil?}
      end

      private
      def initialize_variables
        self.class.need_initialize_variables.each do |variable_name, init_value|
          if init_value.nil?
            value = nil
          else
            if init_value.respond_to?(:call)
              value = init_value.call(self)
            elsif init_value.is_a?(String)
              # just for backward compatibility
              value = instance_eval(init_value, __FILE__, __LINE__)
            else
              value = init_value
            end
          end
          instance_variable_set("@#{variable_name}", value)
        end
      end

      def setup_other_elements(feed, current=nil)
        current ||= current_element(feed)
        self.class.other_elements.each do |element|
          __send__("setup_#{element}", feed, current)
        end
      end

      def current_element(feed)
        feed
      end

      def set_default_values(&block)
        return yield if @default_values_are_set

        begin
          @default_values_are_set = true
          _set_default_values(&block)
        ensure
          @default_values_are_set = false
        end
      end

      def _set_default_values(&block)
        yield
      end

      def setup_values(target)
        set = false
        if have_required_values?
          variables.each do |var|
            setter = "#{var}="
            if target.respond_to?(setter)
              value = __send__(var)
              unless value.nil?
                target.__send__(setter, value)
                set = true
              end
            end
          end
        end
        set
      end

      def set_parent(target, parent)
        target.parent = parent if target.class.need_parent?
      end

      def variables
        self.class.need_initialize_variables.find_all do |name, init|
          # init == "nil" is just for backward compatibility
          init.nil? or init == "nil"
        end.collect do |name, init|
          name
        end
      end

      def not_set_required_variables
        required_variable_names.find_all do |var|
          __send__(var).nil?
        end
      end

      def required_variables_are_set?
        required_variable_names.each do |var|
          return false if __send__(var).nil?
        end
        true
      end
    end

    module AtomPersonConstructBase
      def self.append_features(klass)
        super

        klass.class_eval(<<-EOC, __FILE__, __LINE__ + 1)
          %w(name uri email).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        EOC
      end
    end

    module AtomTextConstructBase
      module EnsureXMLContent
        class << self
          def included(base)
            super
            base.class_eval do
              %w(type content xml_content).each do |element|
                attr_reader element
                attr_writer element if element != "xml_content"
                add_need_initialize_variable(element)
              end

              alias_method(:xhtml, :xml_content)
            end
          end
        end

        def ensure_xml_content(content)
          xhtml_uri = ::RSS::Atom::XHTML_URI
          unless content.is_a?(RSS::XML::Element) and
              ["div", xhtml_uri] == [content.name, content.uri]
            children = content
            children = [children] unless content.is_a?(Array)
            children = set_xhtml_uri_as_default_uri(children)
            content = RSS::XML::Element.new("div", nil, xhtml_uri,
                                            {"xmlns" => xhtml_uri},
                                            children)
          end
          content
        end

        def xml_content=(content)
          @xml_content = ensure_xml_content(content)
        end

        def xhtml=(content)
          self.xml_content = content
        end

        private
        def set_xhtml_uri_as_default_uri(children)
          children.collect do |child|
            if child.is_a?(RSS::XML::Element) and
                child.prefix.nil? and child.uri.nil?
              RSS::XML::Element.new(child.name, nil, ::RSS::Atom::XHTML_URI,
                                    child.attributes.dup,
                                    set_xhtml_uri_as_default_uri(child.children))
            else
              child
            end
          end
        end
      end

      def self.append_features(klass)
        super

        klass.class_eval do
          include EnsureXMLContent
        end
      end
    end

    module SetupDefaultDate
      private
      def _set_default_values
        keep = {
          :date => date,
          :dc_dates => dc_dates.to_a.dup,
        }
        _date = _parse_date_if_needed(date)
        if _date and !dc_dates.any? {|dc_date| dc_date.value == _date}
          dc_date = self.class::DublinCoreDates::DublinCoreDate.new(self)
          dc_date.value = _date.dup
          dc_dates.unshift(dc_date)
        end
        self.date ||= self.dc_date
        super
      ensure
        self.date = keep[:date]
        dc_dates.replace(keep[:dc_dates])
      end

      def _parse_date_if_needed(date_value)
        date_value = Time.parse(date_value) if date_value.is_a?(String)
        date_value
      end
    end

    module SetupDefaultLanguage
      private
      def _set_default_values
        keep = {
          :dc_languages => dc_languages.to_a.dup,
        }
        _language = language
        if _language and
            !dc_languages.any? {|dc_language| dc_language.value == _language}
          dc_language = self.class::DublinCoreLanguages::DublinCoreLanguage.new(self)
          dc_language.value = _language.dup
          dc_languages.unshift(dc_language)
        end
        super
      ensure
        dc_languages.replace(keep[:dc_languages])
      end
    end

    class RSSBase < Base
      class << self
        def make(*args, &block)
          new(*args).make(&block)
        end
      end

      %w(xml_stylesheets channel image items textinput).each do |element|
        attr_reader element
        add_need_initialize_variable(element) do |object|
          object.send("make_#{element}")
        end
        module_eval(<<-EOC, __FILE__, __LINE__ + 1)
          private
          def setup_#{element}(feed)
            @#{element}.to_feed(feed)
          end

          def make_#{element}
            self.class::#{Utils.to_class_name(element)}.new(self)
          end
        EOC
      end

      attr_reader :feed_version
      alias_method(:rss_version, :feed_version)
      attr_accessor :version, :encoding, :standalone

      def initialize(feed_version)
        super(self)
        @feed_type = nil
        @feed_subtype = nil
        @feed_version = feed_version
        @version = "1.0"
        @encoding = "UTF-8"
        @standalone = nil
      end

      def make
        yield(self)
        to_feed
      end

      def to_feed
        feed = make_feed
        setup_xml_stylesheets(feed)
        setup_elements(feed)
        setup_other_elements(feed)
        feed.validate
        feed
      end

      private
      remove_method :make_xml_stylesheets
      def make_xml_stylesheets
        XMLStyleSheets.new(self)
      end
    end

    class XMLStyleSheets < Base
      def_array_element("xml_stylesheet", nil, "XMLStyleSheet")

      class XMLStyleSheet < Base

        ::RSS::XMLStyleSheet::ATTRIBUTES.each do |attribute|
          attr_accessor attribute
          add_need_initialize_variable(attribute)
        end

        def to_feed(feed)
          xss = ::RSS::XMLStyleSheet.new
          guess_type_if_need(xss)
          set = setup_values(xss)
          if set
            feed.xml_stylesheets << xss
          end
        end

        private
        def guess_type_if_need(xss)
          if @type.nil?
            xss.href = @href
            @type = xss.type
          end
        end

        def required_variable_names
          %w(href type)
        end
      end
    end

    class ChannelBase < Base
      include SetupDefaultDate

      %w(cloud categories skipDays skipHours).each do |name|
        def_classed_element(name)
      end

      %w(generator copyright description title).each do |name|
        def_classed_element(name, nil, "content")
      end

      [
       ["link", "href", Proc.new {|target,| "#{target}.href = 'self'"}],
       ["author", "name"],
       ["contributor", "name"],
      ].each do |name, attribute, additional_setup_maker|
        def_classed_elements(name, attribute, &additional_setup_maker)
      end

      %w(id about language
         managingEditor webMaster rating docs ttl).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end

      %w(date lastBuildDate).each do |date_element|
        attr_reader date_element
        add_need_initialize_variable(date_element)
      end

      def date=(_date)
        @date = _parse_date_if_needed(_date)
      end

      def lastBuildDate=(_date)
        @lastBuildDate = _parse_date_if_needed(_date)
      end

      def pubDate
        date
      end

      def pubDate=(date)
        self.date = date
      end

      def updated
        date
      end

      def updated=(date)
        self.date = date
      end

      alias_method(:rights, :copyright)
      alias_method(:rights=, :copyright=)

      alias_method(:subtitle, :description)
      alias_method(:subtitle=, :description=)

      def icon
        image_favicon.about
      end

      def icon=(url)
        image_favicon.about = url
      end

      def logo
        maker.image.url
      end

      def logo=(url)
        maker.image.url = url
      end

      class SkipDaysBase < Base
        def_array_element("day")

        class DayBase < Base
          %w(content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      end

      class SkipHoursBase < Base
        def_array_element("hour")

        class HourBase < Base
          %w(content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      end

      class CloudBase < Base
        %w(domain port path registerProcedure protocol).each do |element|
          attr_accessor element
          add_need_initialize_variable(element)
        end
      end

      class CategoriesBase < Base
        def_array_element("category", "categories")

        class CategoryBase < Base
          %w(domain content label).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end

          alias_method(:term, :domain)
          alias_method(:term=, :domain=)
          alias_method(:scheme, :content)
          alias_method(:scheme=, :content=)
        end
      end

      class LinksBase < Base
        def_array_element("link")

        class LinkBase < Base
          %w(href rel type hreflang title length).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end
      end

      class AuthorsBase < Base
        def_array_element("author")

        class AuthorBase < Base
          include AtomPersonConstructBase
        end
      end

      class ContributorsBase < Base
        def_array_element("contributor")

        class ContributorBase < Base
          include AtomPersonConstructBase
        end
      end

      class GeneratorBase < Base
        %w(uri version content).each do |element|
          attr_accessor element
          add_need_initialize_variable(element)
        end
      end

      class CopyrightBase < Base
        include AtomTextConstructBase
      end

      class DescriptionBase < Base
        include AtomTextConstructBase
      end

      class TitleBase < Base
        include AtomTextConstructBase
      end
    end

    class ImageBase < Base
      %w(title url width height description).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end

      def link
        @maker.channel.link
      end
    end

    class ItemsBase < Base
      def_array_element("item")

      attr_accessor :do_sort, :max_size

      def initialize(maker)
        super
        @do_sort = false
        @max_size = -1
      end

      def normalize
        if @max_size >= 0
          sort_if_need[0...@max_size]
        else
          sort_if_need[0..@max_size]
        end
      end

      private
      def sort_if_need
        if @do_sort.respond_to?(:call)
          @items.sort do |x, y|
            @do_sort.call(x, y)
          end
        elsif @do_sort
          @items.sort do |x, y|
            y <=> x
          end
        else
          @items
        end
      end

      class ItemBase < Base
        include SetupDefaultDate

        %w(guid enclosure source categories content).each do |name|
          def_classed_element(name)
        end

        %w(rights description title).each do |name|
          def_classed_element(name, nil, "content")
        end

        [
         ["author", "name"],
         ["link", "href", Proc.new {|target,| "#{target}.href = 'alternate'"}],
         ["contributor", "name"],
        ].each do |name, attribute|
          def_classed_elements(name, attribute)
        end

        %w(comments id published).each do |element|
          attr_accessor element
          add_need_initialize_variable(element)
        end

        %w(date).each do |date_element|
          attr_reader date_element
          add_need_initialize_variable(date_element)
        end

        def date=(_date)
          @date = _parse_date_if_needed(_date)
        end

        def pubDate
          date
        end

        def pubDate=(date)
          self.date = date
        end

        def updated
          date
        end

        def updated=(date)
          self.date = date
        end

        alias_method(:summary, :description)
        alias_method(:summary=, :description=)

        def <=>(other)
          _date = date || dc_date
          _other_date = other.date || other.dc_date
          if _date and _other_date
            _date <=> _other_date
          elsif _date
            1
          elsif _other_date
            -1
          else
            0
          end
        end

        class GuidBase < Base
          %w(isPermaLink content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end

          def permanent_link?
            isPermaLink
          end

          def permanent_link=(bool)
            self.isPermaLink = bool
          end
        end

        class EnclosureBase < Base
          %w(url length type).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end
        end

        class SourceBase < Base
          include SetupDefaultDate

          %w(authors categories contributors generator icon
             logo rights subtitle title).each do |name|
            def_classed_element(name)
          end

          [
           ["link", "href"],
          ].each do |name, attribute|
            def_classed_elements(name, attribute)
          end

          %w(id content).each do |element|
            attr_accessor element
            add_need_initialize_variable(element)
          end

          alias_method(:url, :link)
          alias_method(:url=, :link=)

          %w(date).each do |date_element|
            attr_reader date_element
            add_need_initialize_variable(date_element)
          end

          def date=(_date)
            @date = _parse_date_if_needed(_date)
          end

          def updated
            date
          end

          def updated=(date)
            self.date = date
          end

          private
          AuthorsBase = ChannelBase::AuthorsBase
          CategoriesBase = ChannelBase::CategoriesBase
          ContributorsBase = ChannelBase::ContributorsBase
          GeneratorBase = ChannelBase::GeneratorBase

          class IconBase < Base
            %w(url).each do |element|
              attr_accessor element
              add_need_initialize_variable(element)
            end
          end

          LinksBase = ChannelBase::LinksBase

          class LogoBase < Base
            %w(uri).each do |element|
              attr_accessor element
              add_need_initialize_variable(element)
            end
          end

          class RightsBase < Base
            include AtomTextConstructBase
          end

          class SubtitleBase < Base
            include AtomTextConstructBase
          end

          class TitleBase < Base
            include AtomTextConstructBase
          end
        end

        CategoriesBase = ChannelBase::CategoriesBase
        AuthorsBase = ChannelBase::AuthorsBase
        LinksBase = ChannelBase::LinksBase
        ContributorsBase = ChannelBase::ContributorsBase

        class RightsBase < Base
          include AtomTextConstructBase
        end

        class DescriptionBase < Base
          include AtomTextConstructBase
        end

        class ContentBase < Base
          include AtomTextConstructBase::EnsureXMLContent

          %w(src).each do |element|
            attr_accessor(element)
            add_need_initialize_variable(element)
          end

          def xml_content=(content)
            content = ensure_xml_content(content) if inline_xhtml?
            @xml_content = content
          end

          alias_method(:xml, :xml_content)
          alias_method(:xml=, :xml_content=)

          def inline_text?
            [nil, "text", "html"].include?(@type)
          end

          def inline_html?
            @type == "html"
          end

          def inline_xhtml?
            @type == "xhtml"
          end

          def inline_other?
            !out_of_line? and ![nil, "text", "html", "xhtml"].include?(@type)
          end

          def inline_other_text?
            return false if @type.nil? or out_of_line?
            /\Atext\//i.match(@type) ? true : false
          end

          def inline_other_xml?
            return false if @type.nil? or out_of_line?
            /[\+\/]xml\z/i.match(@type) ? true : false
          end

          def inline_other_base64?
            return false if @type.nil? or out_of_line?
            @type.include?("/") and !inline_other_text? and !inline_other_xml?
          end

          def out_of_line?
            not @src.nil? and @content.nil?
          end
        end

        class TitleBase < Base
          include AtomTextConstructBase
        end
      end
    end

    class TextinputBase < Base
      %w(title description name link).each do |element|
        attr_accessor element
        add_need_initialize_variable(element)
      end
    end
  end
end
