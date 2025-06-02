# frozen_string_literal: false
require_relative "../atom"

require_relative "base"

module RSS
  module Maker
    module AtomPersons
      module_function
      def def_atom_persons(klass, name, maker_name, plural=nil)
        plural ||= "#{name}s"
        klass_name = Utils.to_class_name(name)
        plural_klass_name = Utils.to_class_name(plural)

        klass.class_eval(<<-EOC, __FILE__, __LINE__ + 1)
          class #{plural_klass_name} < #{plural_klass_name}Base
            class #{klass_name} < #{klass_name}Base
              def to_feed(feed, current)
                #{name} = feed.class::#{klass_name}.new
                set = setup_values(#{name})
                unless set
                  raise NotSetError.new(#{maker_name.dump},
                                        not_set_required_variables)
                end
                current.#{plural} << #{name}
                set_parent(#{name}, current)
                setup_other_elements(#{name})
              end

              private
              def required_variable_names
                %w(name)
              end
            end
          end
EOC
      end
    end

    module AtomTextConstruct
      class << self
        def def_atom_text_construct(klass, name, maker_name, klass_name=nil,
                                    atom_klass_name=nil)
          klass_name ||= Utils.to_class_name(name)
          atom_klass_name ||= Utils.to_class_name(name)

          klass.class_eval(<<-EOC, __FILE__, __LINE__ + 1)
            class #{klass_name} < #{klass_name}Base
              include #{self.name}
              def to_feed(feed, current)
                #{name} = current.class::#{atom_klass_name}.new
                if setup_values(#{name})
                  current.#{name} = #{name}
                  set_parent(#{name}, current)
                  setup_other_elements(feed)
                elsif variable_is_set?
                  raise NotSetError.new(#{maker_name.dump},
                                        not_set_required_variables)
                end
              end
            end
          EOC
        end
      end

      private
      def required_variable_names
        if type == "xhtml"
          %w(xml_content)
        else
          %w(content)
        end
      end

      def variables
        if type == "xhtml"
          super + %w(xhtml)
        else
          super
        end
      end
    end

    module AtomCategory
      def to_feed(feed, current)
        category = feed.class::Category.new
        set = setup_values(category)
        if set
          current.categories << category
          set_parent(category, current)
          setup_other_elements(feed)
        else
          raise NotSetError.new(self.class.not_set_name,
                                not_set_required_variables)
        end
      end

      private
      def required_variable_names
        %w(term)
      end

      def variables
        super + ["term", "scheme"]
      end
    end

    module AtomLink
      def to_feed(feed, current)
        link = feed.class::Link.new
        set = setup_values(link)
        if set
          current.links << link
          set_parent(link, current)
          setup_other_elements(feed)
        else
          raise NotSetError.new(self.class.not_set_name,
                                not_set_required_variables)
        end
      end

      private
      def required_variable_names
        %w(href)
      end
    end

    module AtomGenerator
      def to_feed(feed, current)
        generator = current.class::Generator.new
        if setup_values(generator)
          current.generator = generator
          set_parent(generator, current)
          setup_other_elements(feed)
        elsif variable_is_set?
          raise NotSetError.new(self.class.not_set_name,
                                not_set_required_variables)
        end
      end

      private
      def required_variable_names
        %w(content)
      end
    end

    module AtomLogo
      def to_feed(feed, current)
        logo = current.class::Logo.new
        class << logo
          alias_method(:uri=, :content=)
        end
        set = setup_values(logo)
        class << logo
          remove_method(:uri=)
        end
        if set
          current.logo = logo
          set_parent(logo, current)
          setup_other_elements(feed)
        elsif variable_is_set?
          raise NotSetError.new(self.class.not_set_name,
                                not_set_required_variables)
        end
      end

      private
      def required_variable_names
        %w(uri)
      end
    end
  end
end
