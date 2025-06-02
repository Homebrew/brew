# frozen_string_literal: false
# This file contains the implementation of trackbacks. It is entirely internal
# and not useful to outside developers.
require 'rss/1.0'
require 'rss/2.0'

module RSS # :nodoc: all

  TRACKBACK_PREFIX = 'trackback'
  TRACKBACK_URI = 'http://madskills.com/public/xml/rss/module/trackback/'

  RDF.install_ns(TRACKBACK_PREFIX, TRACKBACK_URI)
  Rss.install_ns(TRACKBACK_PREFIX, TRACKBACK_URI)

  module TrackBackUtils
    private
    def trackback_validate(ignore_unknown_element, tags, uri)
      return if tags.nil?
      if tags.find {|tag| tag == "about"} and
          !tags.find {|tag| tag == "ping"}
        raise MissingTagError.new("#{TRACKBACK_PREFIX}:ping", tag_name)
      end
    end
  end

  module BaseTrackBackModel

    ELEMENTS = %w(ping about)

    def append_features(klass)
      super

      unless klass.class == Module
        klass.module_eval {include TrackBackUtils}

        klass.install_must_call_validator(TRACKBACK_PREFIX, TRACKBACK_URI)
        %w(ping).each do |name|
          var_name = "#{TRACKBACK_PREFIX}_#{name}"
          klass_name = "TrackBack#{Utils.to_class_name(name)}"
          klass.install_have_child_element(name, TRACKBACK_URI, "?", var_name)
          klass.module_eval(<<-EOC, __FILE__, __LINE__)
            remove_method :#{var_name}
            def #{var_name}
              @#{var_name} and @#{var_name}.value
            end

            remove_method :#{var_name}=
            def #{var_name}=(value)
              @#{var_name} = Utils.new_with_value_if_need(#{klass_name}, value)
            end
          EOC
        end

        [%w(about s)].each do |name, postfix|
          var_name = "#{TRACKBACK_PREFIX}_#{name}"
          klass_name = "TrackBack#{Utils.to_class_name(name)}"
          klass.install_have_children_element(name, TRACKBACK_URI, "*",
                                              var_name)
          klass.module_eval(<<-EOC, __FILE__, __LINE__)
            remove_method :#{var_name}
            def #{var_name}(*args)
              if args.empty?
                @#{var_name}.first and @#{var_name}.first.value
              else
                ret = @#{var_name}.__send__("[]", *args)
                if ret.is_a?(Array)
                  ret.collect {|x| x.value}
                else
                  ret.value
                end
              end
            end

            remove_method :#{var_name}=
            remove_method :set_#{var_name}
            def #{var_name}=(*args)
              if args.size == 1
                item = Utils.new_with_value_if_need(#{klass_name}, args[0])
                @#{var_name}.push(item)
              else
                new_val = args.last
                if new_val.is_a?(Array)
                  new_val = new_value.collect do |val|
                    Utils.new_with_value_if_need(#{klass_name}, val)
                  end
                else
                  new_val = Utils.new_with_value_if_need(#{klass_name}, new_val)
                end
                @#{var_name}.__send__("[]=", *(args[0..-2] + [new_val]))
              end
            end
            alias set_#{var_name} #{var_name}=
          EOC
        end
      end
    end
  end

  module TrackBackModel10
    extend BaseModel
    extend BaseTrackBackModel

    class TrackBackPing < Element
      include RSS10

      class << self

        def required_prefix
          TRACKBACK_PREFIX
        end

        def required_uri
          TRACKBACK_URI
        end

      end

      @tag_name = "ping"

      [
        ["resource", ::RSS::RDF::URI, true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required, nil, nil,
                              "#{::RSS::RDF::PREFIX}:#{name}")
      end

      alias_method(:value, :resource)
      alias_method(:value=, :resource=)
      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.resource = args[0]
        end
      end

      def full_name
        tag_name_with_prefix(TRACKBACK_PREFIX)
      end
    end

    class TrackBackAbout < Element
      include RSS10

      class << self

        def required_prefix
          TRACKBACK_PREFIX
        end

        def required_uri
          TRACKBACK_URI
        end

      end

      @tag_name = "about"

      [
        ["resource", ::RSS::RDF::URI, true]
      ].each do |name, uri, required|
        install_get_attribute(name, uri, required, nil, nil,
                              "#{::RSS::RDF::PREFIX}:#{name}")
      end

      alias_method(:value, :resource)
      alias_method(:value=, :resource=)

      def initialize(*args)
        if Utils.element_initialize_arguments?(args)
          super
        else
          super()
          self.resource = args[0]
        end
      end

      def full_name
        tag_name_with_prefix(TRACKBACK_PREFIX)
      end

      private
      def maker_target(abouts)
        abouts.new_about
      end

      def setup_maker_attributes(about)
        about.resource = self.resource
      end

    end
  end

  module TrackBackModel20
    extend BaseModel
    extend BaseTrackBackModel

    class TrackBackPing < Element
      include RSS09

      @tag_name = "ping"

      content_setup

      class << self

        def required_prefix
          TRACKBACK_PREFIX
        end

        def required_uri
          TRACKBACK_URI
        end

      end

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
        tag_name_with_prefix(TRACKBACK_PREFIX)
      end

    end

    class TrackBackAbout < Element
      include RSS09

      @tag_name = "about"

      content_setup

      class << self

        def required_prefix
          TRACKBACK_PREFIX
        end

        def required_uri
          TRACKBACK_URI
        end

      end

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
        tag_name_with_prefix(TRACKBACK_PREFIX)
      end

    end
  end

  class RDF
    class Item; include TrackBackModel10; end
  end

  class Rss
    class Channel
      class Item; include TrackBackModel20; end
    end
  end

  BaseTrackBackModel::ELEMENTS.each do |name|
    class_name = Utils.to_class_name(name)
    BaseListener.install_class_name(TRACKBACK_URI, name,
                                    "TrackBack#{class_name}")
  end

  BaseTrackBackModel::ELEMENTS.collect! {|name| "#{TRACKBACK_PREFIX}_#{name}"}
end
