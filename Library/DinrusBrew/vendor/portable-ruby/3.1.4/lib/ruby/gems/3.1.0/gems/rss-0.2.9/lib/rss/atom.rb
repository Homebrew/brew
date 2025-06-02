# frozen_string_literal: false
require_relative 'parser'

module RSS
  ##
  # Atom is an XML-based document format that is used to describe 'feeds' of related information.
  # A typical use is in a news feed where the information is periodically updated and which users
  # can subscribe to.  The Atom format is described in http://tools.ietf.org/html/rfc4287
  #
  # The Atom module provides support in reading and creating feeds.
  #
  # See the RSS module for examples consuming and creating feeds.
  module Atom

    ##
    # The Atom URI W3C Namespace

    URI = "http://www.w3.org/2005/Atom"

    ##
    # The XHTML URI W3C Namespace

    XHTML_URI = "http://www.w3.org/1999/xhtml"

    module CommonModel
      NSPOOL = {}
      ELEMENTS = []

      def self.append_features(klass)
        super
        klass.install_must_call_validator("atom", URI)
        [
         ["lang", :xml],
         ["base", :xml],
        ].each do |name, uri, required|
          klass.install_get_attribute(name, uri, required, [nil, :inherit])
        end
        klass.class_eval do
          class << self
            # Returns the Atom URI W3C Namespace
            def required_uri
              URI
            end

            # Returns true
            def need_parent?
              true
            end
          end
        end
      end
    end

    module ContentModel
      module ClassMethods
        def content_type
          @content_type ||= nil
        end
      end

      class << self
        def append_features(klass)
          super
          klass.extend(ClassMethods)
          klass.content_setup(klass.content_type, klass.tag_name)
        end
      end

      def maker_target(target)
        target
      end

      private
      def setup_maker_element_writer
        "#{self.class.name.split(/::/).last.downcase}="
      end

      def setup_maker_element(target)
        target.__send__(setup_maker_element_writer, content)
        super
      end
    end

    module URIContentModel
      class  << self
        def append_features(klass)
          super
          klass.class_eval do
            @content_type = [nil, :uri]
            include(ContentModel)
          end
        end
      end
    end

    # The TextConstruct module is used to define a Text construct Atom element,
    # which is used to store small quantities of human-readable text.
    #
    # The TextConstruct has a type attribute, e.g. text, html, xhtml
    #
    # Reference: https://validator.w3.org/feed/docs/rfc4287.html#text.constructs
    module TextConstruct
      def self.append_features(klass)
        super
        klass.class_eval do
          [
           ["type", ""],
          ].each do |name, uri, required|
            install_get_attribute(name, uri, required, :text_type)
          end

          content_setup
          add_need_initialize_variable("xhtml")

          class << self
            def xml_getter
              "xhtml"
            end

            def xml_setter
              "xhtml="
            end
          end
        end
      end

      attr_writer :xhtml

      # Returns or builds the XHTML content.
      def xhtml
        return @xhtml if @xhtml.nil?
        if @xhtml.is_a?(XML::Element) and
            [@xhtml.name, @xhtml.uri] == ["div", XHTML_URI]
          return @xhtml
        end

        children = @xhtml
        children = [children] unless children.is_a?(Array)
        XML::Element.new("div", nil, XHTML_URI,
                         {"xmlns" => XHTML_URI}, children)
      end

      # Returns true if type is "xhtml".
      def have_xml_content?
        @type == "xhtml"
      end

      # Raises a MissingTagError or NotExpectedTagError
      # if the element is not properly formatted.
      def atom_validate(ignore_unknown_element, tags, uri)
        if have_xml_content?
          if @xhtml.nil?
            raise MissingTagError.new("div", tag_name)
          end
          unless [@xhtml.name, @xhtml.uri] == ["div", XHTML_URI]
            raise NotExpectedTagError.new(@xhtml.name, @xhtml.uri, tag_name)
          end
        end
      end

      private
      def maker_target(target)
        target.__send__(self.class.name.split(/::/).last.downcase) {|x| x}
      end

      def setup_maker_attributes(target)
        target.type = type
        target.content = content
        target.xml_content = @xhtml
      end
    end

    # The PersonConstruct module is used to define a person Atom element that can be
    # used to describe a person, corporation or similar entity.
    #
    # The PersonConstruct has a Name, Uri and Email child elements.
    #
    # Reference: https://validator.w3.org/feed/docs/rfc4287.html#atomPersonConstruct
    module PersonConstruct

      # Adds attributes for name, uri, and email to the +klass+
      def self.append_features(klass)
        super
        klass.class_eval do
          [
           ["name", nil],
           ["uri", "?"],
           ["email", "?"],
          ].each do |tag, occurs|
            install_have_attribute_element(tag, URI, occurs, nil, :content)
          end
        end
      end

      def maker_target(target)
        target.__send__("new_#{self.class.name.split(/::/).last.downcase}")
      end

      # The name of the person or entity.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.name
      class Name < RSS::Element
        include CommonModel
        include ContentModel
      end

      # The URI of the person or entity.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.uri
      class Uri < RSS::Element
        include CommonModel
        include URIContentModel
      end

      # The email of the person or entity.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.email
      class Email < RSS::Element
        include CommonModel
        include ContentModel
      end
    end

    # Element used to describe an Atom date and time in the ISO 8601 format
    #
    # Examples:
    # * 2013-03-04T15:30:02Z
    # * 2013-03-04T10:30:02-05:00
    module DateConstruct
      def self.append_features(klass)
        super
        klass.class_eval do
          @content_type = :w3cdtf
          include(ContentModel)
        end
      end

      # Raises NotAvailableValueError if element content is nil
      def atom_validate(ignore_unknown_element, tags, uri)
        raise NotAvailableValueError.new(tag_name, "") if content.nil?
      end
    end

    module DuplicateLinkChecker
      # Checks if there are duplicate links with the same type and hreflang attributes
      # that have an alternate (or empty) rel attribute
      #
      # Raises a TooMuchTagError if there are duplicates found
      def validate_duplicate_links(links)
        link_infos = {}
        links.each do |link|
          rel = link.rel || "alternate"
          next unless rel == "alternate"
          key = [link.hreflang, link.type]
          if link_infos.has_key?(key)
            raise TooMuchTagError.new("link", tag_name)
          end
          link_infos[key] = true
        end
      end
    end

    # Defines the top-level element of an Atom Feed Document.
    # It consists of a number of children Entry elements,
    # and has the following attributes:
    #
    # * author
    # * categories
    # * category
    # * content
    # * contributor
    # * entries (aliased as items)
    # * entry
    # * generator
    # * icon
    # * id
    # * link
    # * logo
    # * rights
    # * subtitle
    # * title
    # * updated
    #
    # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.feed
    class Feed < RSS::Element
      include RootElementMixin
      include CommonModel
      include DuplicateLinkChecker

      install_ns('', URI)

      [
       ["author", "*", :children],
       ["category", "*", :children, "categories"],
       ["contributor", "*", :children],
       ["generator", "?"],
       ["icon", "?", nil, :content],
       ["id", nil, nil, :content],
       ["link", "*", :children],
       ["logo", "?"],
       ["rights", "?"],
       ["subtitle", "?", nil, :content],
       ["title", nil, nil, :content],
       ["updated", nil, nil, :content],
       ["entry", "*", :children, "entries"],
      ].each do |tag, occurs, type, *args|
        type ||= :child
        __send__("install_have_#{type}_element",
                 tag, URI, occurs, tag, *args)
      end

      # Creates a new Atom feed
      def initialize(version=nil, encoding=nil, standalone=nil)
        super("1.0", version, encoding, standalone)
        @feed_type = "atom"
        @feed_subtype = "feed"
      end

      alias_method :items, :entries

      # Returns true if there are any authors for the feed or any of the Entry
      # child elements have an author
      def have_author?
        authors.any? {|author| !author.to_s.empty?} or
          entries.any? {|entry| entry.have_author?(false)}
      end

      private
      def atom_validate(ignore_unknown_element, tags, uri)
        unless have_author?
          raise MissingTagError.new("author", tag_name)
        end
        validate_duplicate_links(links)
      end

      def have_required_elements?
        super and have_author?
      end

      def maker_target(maker)
        maker.channel
      end

      def setup_maker_element(channel)
        prev_dc_dates = channel.dc_dates.to_a.dup
        super
        channel.about = id.content if id
        channel.dc_dates.replace(prev_dc_dates)
      end

      def setup_maker_elements(channel)
        super
        items = channel.maker.items
        entries.each do |entry|
          entry.setup_maker(items)
        end
      end

      # PersonConstruct that contains information regarding the author
      # of a Feed or Entry.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.author
      class Author < RSS::Element
        include CommonModel
        include PersonConstruct
      end

      # Contains information about a category associated with a Feed or Entry.
      # It has the following attributes:
      #
      # * term
      # * scheme
      # * label
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.category
      class Category < RSS::Element
        include CommonModel

        [
         ["term", "", true],
         ["scheme", "", false, [nil, :uri]],
         ["label", ""],
        ].each do |name, uri, required, type|
          install_get_attribute(name, uri, required, type)
        end

        private
        def maker_target(target)
          target.new_category
        end
      end

      # PersonConstruct that contains information regarding the
      # contributors of a Feed or Entry.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.contributor
      class Contributor < RSS::Element
        include CommonModel
        include PersonConstruct
      end

      # Contains information on the agent used to generate the feed.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.generator
      class Generator < RSS::Element
        include CommonModel
        include ContentModel

        [
         ["uri", "", false, [nil, :uri]],
         ["version", ""],
        ].each do |name, uri, required, type|
          install_get_attribute(name, uri, required, type)
        end

        private
        def setup_maker_attributes(target)
          target.generator do |generator|
            generator.uri = uri if uri
            generator.version = version if version
          end
        end
      end

      # Defines an image that provides a visual identification for a eed.
      # The image should have an aspect ratio of 1:1.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.icon
      class Icon < RSS::Element
        include CommonModel
        include URIContentModel
      end

      # Defines the Universally Unique Identifier (UUID) for a Feed or Entry.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.id
      class Id < RSS::Element
        include CommonModel
        include URIContentModel
      end

      # Defines a reference to a Web resource. It has the following
      # attributes:
      #
      # * href
      # * rel
      # * type
      # * hreflang
      # * title
      # * length
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.link
      class Link < RSS::Element
        include CommonModel

        [
         ["href", "", true, [nil, :uri]],
         ["rel", ""],
         ["type", ""],
         ["hreflang", ""],
         ["title", ""],
         ["length", ""],
        ].each do |name, uri, required, type|
          install_get_attribute(name, uri, required, type)
        end

        private
        def maker_target(target)
          target.new_link
        end
      end

      # Defines an image that provides a visual identification for the Feed.
      # The image should have an aspect ratio of 2:1 (horizontal:vertical).
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.logo
      class Logo < RSS::Element
        include CommonModel
        include URIContentModel

        def maker_target(target)
          target.maker.image
        end

        private
        def setup_maker_element_writer
          "url="
        end
      end

      # TextConstruct that contains copyright information regarding
      # the content in an Entry or Feed. It should not be used to
      # convey machine readable licensing information.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.rights
      class Rights < RSS::Element
        include CommonModel
        include TextConstruct
      end

      # TextConstruct that conveys a description or subtitle for a Feed.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.subtitle
      class Subtitle < RSS::Element
        include CommonModel
        include TextConstruct
      end

      # TextConstruct that conveys a description or title for a Feed or Entry.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.title
      class Title < RSS::Element
        include CommonModel
        include TextConstruct
      end

      # DateConstruct indicating the most recent time when a Feed or
      # Entry was modified in a way the publisher considers
      # significant.
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.updated
      class Updated < RSS::Element
        include CommonModel
        include DateConstruct
      end

      # Defines a child Atom Entry element of an Atom Feed element.
      # It has the following attributes:
      #
      # * author
      # * category
      # * categories
      # * content
      # * contributor
      # * id
      # * link
      # * published
      # * rights
      # * source
      # * summary
      # * title
      # * updated
      #
      # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.entry
      class Entry < RSS::Element
        include CommonModel
        include DuplicateLinkChecker

        [
         ["author", "*", :children],
         ["category", "*", :children, "categories"],
         ["content", "?", :child],
         ["contributor", "*", :children],
         ["id", nil, nil, :content],
         ["link", "*", :children],
         ["published", "?", :child, :content],
         ["rights", "?", :child],
         ["source", "?"],
         ["summary", "?", :child],
         ["title", nil],
         ["updated", nil, :child, :content],
        ].each do |tag, occurs, type, *args|
          type ||= :attribute
          __send__("install_have_#{type}_element",
                   tag, URI, occurs, tag, *args)
        end

        # Returns whether any of the following are true:
        #
        # * There are any authors in the feed
        # * If the parent element has an author and the +check_parent+
        #   parameter was given.
        # * There is a source element that has an author
        def have_author?(check_parent=true)
          authors.any? {|author| !author.to_s.empty?} or
            (check_parent and @parent and @parent.have_author?) or
            (source and source.have_author?)
        end

        private
        def atom_validate(ignore_unknown_element, tags, uri)
          unless have_author?
            raise MissingTagError.new("author", tag_name)
          end
          validate_duplicate_links(links)
        end

        def have_required_elements?
          super and have_author?
        end

        def maker_target(items)
          if items.respond_to?("items")
            # For backward compatibility
            items = items.items
          end
          items.new_item
        end

        # Feed::Author
        Author = Feed::Author
        # Feed::Category
        Category = Feed::Category

        # Contains or links to the content of the Entry.
        # It has the following attributes:
        #
        # * type
        # * src
        #
        # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.content
        class Content < RSS::Element
          include CommonModel

          class << self
            def xml_setter
              "xml="
            end

            def xml_getter
              "xml"
            end
          end

          [
           ["type", ""],
           ["src", "", false, [nil, :uri]],
          ].each do |name, uri, required, type|
            install_get_attribute(name, uri, required, type)
          end

          content_setup
          add_need_initialize_variable("xml")

          # Returns the element content in XML.
          attr_writer :xml

          # Returns true if the element has inline XML content.
          def have_xml_content?
            inline_xhtml? or inline_other_xml?
          end

          # Returns or builds the element content in XML.
          def xml
            return @xml unless inline_xhtml?
            return @xml if @xml.nil?
            if @xml.is_a?(XML::Element) and
                [@xml.name, @xml.uri] == ["div", XHTML_URI]
              return @xml
            end

            children = @xml
            children = [children] unless children.is_a?(Array)
            XML::Element.new("div", nil, XHTML_URI,
                             {"xmlns" => XHTML_URI}, children)
          end

          # Returns the element content in XHTML.
          def xhtml
            if inline_xhtml?
              xml
            else
              nil
            end
          end

          # Raises a MissingAttributeError, NotAvailableValueError,
          # MissingTagError or NotExpectedTagError if the element is
          # not properly formatted.
          def atom_validate(ignore_unknown_element, tags, uri)
            if out_of_line?
              raise MissingAttributeError.new(tag_name, "type") if @type.nil?
              unless (content.nil? or content.empty?)
                raise NotAvailableValueError.new(tag_name, content)
              end
            elsif inline_xhtml?
              if @xml.nil?
                raise MissingTagError.new("div", tag_name)
              end
              unless @xml.name == "div" and @xml.uri == XHTML_URI
                raise NotExpectedTagError.new(@xml.name, @xml.uri, tag_name)
              end
            end
          end

          # Returns true if the element contains inline content
          # that has a text or HTML media type, or no media type at all.
          def inline_text?
            !out_of_line? and [nil, "text", "html"].include?(@type)
          end

          # Returns true if the element contains inline content that
          # has a HTML media type.
          def inline_html?
            return false if out_of_line?
            @type == "html" or mime_split == ["text", "html"]
          end

          # Returns true if the element contains inline content that
          # has a XHTML media type.
          def inline_xhtml?
            !out_of_line? and @type == "xhtml"
          end

          # Returns true if the element contains inline content that
          # has a MIME media type.
          def inline_other?
            return false if out_of_line?
            media_type, subtype = mime_split
            return false if media_type.nil? or subtype.nil?
            true
          end

          # Returns true if the element contains inline content that
          # has a text media type.
          def inline_other_text?
            return false unless inline_other?
            return false if inline_other_xml?

            media_type, = mime_split
            return true if "text" == media_type.downcase
            false
          end

          # Returns true if the element contains inline content that
          # has a XML media type.
          def inline_other_xml?
            return false unless inline_other?

            media_type, subtype = mime_split
            normalized_mime_type = "#{media_type}/#{subtype}".downcase
            if /(?:\+xml|^xml)$/ =~ subtype or
                %w(text/xml-external-parsed-entity
                   application/xml-external-parsed-entity
                   application/xml-dtd).find {|x| x == normalized_mime_type}
              return true
            end
            false
          end

          # Returns true if the element contains inline content
          # encoded in base64.
          def inline_other_base64?
            inline_other? and !inline_other_text? and !inline_other_xml?
          end

          # Returns true if the element contains linked content.
          def out_of_line?
            not @src.nil?
          end

          # Splits the type attribute into an array, e.g. ["text", "xml"]
          def mime_split
            media_type = subtype = nil
            if /\A\s*([a-z]+)\/([a-z\+]+)\s*(?:;.*)?\z/i =~ @type.to_s
              media_type = $1.downcase
              subtype = $2.downcase
            end
            [media_type, subtype]
          end

          # Returns true if the content needs to be encoded in base64.
          def need_base64_encode?
            inline_other_base64?
          end

          private
          def empty_content?
            out_of_line? or super
          end
        end

        # Feed::Contributor
        Contributor = Feed::Contributor
        # Feed::Id
        Id = Feed::Id
        # Feed::Link
        Link = Feed::Link

        # DateConstruct that usually indicates the time of the initial
        # creation of an Entry.
        #
        # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.published
        class Published < RSS::Element
          include CommonModel
          include DateConstruct
        end

        # Feed::Rights
        Rights = Feed::Rights

        # Defines a Atom Source element. It has the following attributes:
        #
        # * author
        # * category
        # * categories
        # * content
        # * contributor
        # * generator
        # * icon
        # * id
        # * link
        # * logo
        # * rights
        # * subtitle
        # * title
        # * updated
        #
        # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.source
        class Source < RSS::Element
          include CommonModel

          [
           ["author", "*", :children],
           ["category", "*", :children, "categories"],
           ["contributor", "*", :children],
           ["generator", "?"],
           ["icon", "?"],
           ["id", "?", nil, :content],
           ["link", "*", :children],
           ["logo", "?"],
           ["rights", "?"],
           ["subtitle", "?"],
           ["title", "?"],
           ["updated", "?", nil, :content],
          ].each do |tag, occurs, type, *args|
            type ||= :attribute
            __send__("install_have_#{type}_element",
                     tag, URI, occurs, tag, *args)
          end

          # Returns true if the Source element has an author.
          def have_author?
            !author.to_s.empty?
          end

          # Feed::Author
          Author = Feed::Author
          # Feed::Category
          Category = Feed::Category
          # Feed::Contributor
          Contributor = Feed::Contributor
          # Feed::Generator
          Generator = Feed::Generator
          # Feed::Icon
          Icon = Feed::Icon
          # Feed::Id
          Id = Feed::Id
          # Feed::Link
          Link = Feed::Link
          # Feed::Logo
          Logo = Feed::Logo
          # Feed::Rights
          Rights = Feed::Rights
          # Feed::Subtitle
          Subtitle = Feed::Subtitle
          # Feed::Title
          Title = Feed::Title
          # Feed::Updated
          Updated = Feed::Updated
        end

        # TextConstruct that describes a summary of the Entry.
        #
        # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.summary
        class Summary < RSS::Element
          include CommonModel
          include TextConstruct
        end

        # Feed::Title
        Title = Feed::Title
        # Feed::Updated
        Updated = Feed::Updated
      end
    end

    # Defines a top-level Atom Entry element,
    # used as the document element of a stand-alone Atom Entry Document.
    # It has the following attributes:
    #
    # * author
    # * category
    # * categories
    # * content
    # * contributor
    # * id
    # * link
    # * published
    # * rights
    # * source
    # * summary
    # * title
    # * updated
    #
    # Reference: https://validator.w3.org/feed/docs/rfc4287.html#element.entry]
    class Entry < RSS::Element
      include RootElementMixin
      include CommonModel
      include DuplicateLinkChecker

      [
       ["author", "*", :children],
       ["category", "*", :children, "categories"],
       ["content", "?"],
       ["contributor", "*", :children],
       ["id", nil, nil, :content],
       ["link", "*", :children],
       ["published", "?", :child, :content],
       ["rights", "?"],
       ["source", "?"],
       ["summary", "?"],
       ["title", nil],
       ["updated", nil, nil, :content],
      ].each do |tag, occurs, type, *args|
        type ||= :attribute
        __send__("install_have_#{type}_element",
                 tag, URI, occurs, tag, *args)
      end

      # Creates a new Atom Entry element.
      def initialize(version=nil, encoding=nil, standalone=nil)
        super("1.0", version, encoding, standalone)
        @feed_type = "atom"
        @feed_subtype = "entry"
      end

      # Returns the Entry in an array.
      def items
        [self]
      end

      # Sets up the +maker+ for constructing Entry elements.
      def setup_maker(maker)
        maker = maker.maker if maker.respond_to?("maker")
        super(maker)
      end

      # Returns where there are any authors present or there is a
      # source with an author.
      def have_author?
        authors.any? {|author| !author.to_s.empty?} or
          (source and source.have_author?)
      end

      private
      def atom_validate(ignore_unknown_element, tags, uri)
        unless have_author?
          raise MissingTagError.new("author", tag_name)
        end
        validate_duplicate_links(links)
      end

      def have_required_elements?
        super and have_author?
      end

      def maker_target(maker)
        maker.items.new_item
      end

      # Feed::Entry::Author
      Author = Feed::Entry::Author
      # Feed::Entry::Category
      Category = Feed::Entry::Category
      # Feed::Entry::Content
      Content = Feed::Entry::Content
      # Feed::Entry::Contributor
      Contributor = Feed::Entry::Contributor
      # Feed::Entry::Id
      Id = Feed::Entry::Id
      # Feed::Entry::Link
      Link = Feed::Entry::Link
      # Feed::Entry::Published
      Published = Feed::Entry::Published
      # Feed::Entry::Rights
      Rights = Feed::Entry::Rights
      # Feed::Entry::Source
      Source = Feed::Entry::Source
      # Feed::Entry::Summary
      Summary = Feed::Entry::Summary
      # Feed::Entry::Title
      Title = Feed::Entry::Title
      # Feed::Entry::Updated
      Updated = Feed::Entry::Updated
    end
  end

  Atom::CommonModel::ELEMENTS.each do |name|
    BaseListener.install_get_text_element(Atom::URI, name, "#{name}=")
  end

  module ListenerMixin
    private
    def initial_start_feed(tag_name, prefix, attrs, ns)
      check_ns(tag_name, prefix, ns, Atom::URI, false)

      @rss = Atom::Feed.new(@version, @encoding, @standalone)
      @rss.do_validate = @do_validate
      @rss.xml_stylesheets = @xml_stylesheets
      @rss.lang = attrs["xml:lang"]
      @rss.base = attrs["xml:base"]
      @last_element = @rss
      pr = Proc.new do |text, tags|
        @rss.validate_for_stream(tags) if @do_validate
      end
      @proc_stack.push(pr)
    end

    def initial_start_entry(tag_name, prefix, attrs, ns)
      check_ns(tag_name, prefix, ns, Atom::URI, false)

      @rss = Atom::Entry.new(@version, @encoding, @standalone)
      @rss.do_validate = @do_validate
      @rss.xml_stylesheets = @xml_stylesheets
      @rss.lang = attrs["xml:lang"]
      @rss.base = attrs["xml:base"]
      @last_element = @rss
      pr = Proc.new do |text, tags|
        @rss.validate_for_stream(tags) if @do_validate
      end
      @proc_stack.push(pr)
    end
  end
end
