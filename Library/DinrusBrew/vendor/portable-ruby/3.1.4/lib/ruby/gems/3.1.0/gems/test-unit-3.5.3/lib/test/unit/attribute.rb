module Test
  module Unit
    module Attribute
      class StringifyKeyHash < Hash
        class << self
          def stringify(object)
            object.to_s
          end
        end

        def key?(key)
          super(self.class.stringify(key))
        end

        def [](key)
          super(self.class.stringify(key))
        end

        def []=(key, value)
          super(self.class.stringify(key), value)
        end
      end

      class << self
        def included(base)
          base.extend(BaseClassMethods)
          base.extend(ClassMethods)
        end
      end

      module BaseClassMethods
        def attributes_table
          {}
        end
      end

      module ClassMethods
        def method_added(name)
          super
          return unless defined?(@current_attributes)

          attributes = {}
          kept_attributes = StringifyKeyHash.new
          @current_attributes.each do |attribute_name, attribute|
            attributes[attribute_name] = attribute[:value]
            if attribute[:keep]
              keep_hook = attribute[:keep_hook]
              attribute = keep_hook.call(attribute) if keep_hook
              kept_attributes[attribute_name] = attribute
            end
          end
          set_attributes(name, attributes)
          @current_attributes = kept_attributes
        end

        # Set an attribute to test methods.
        #
        # @overload attribute(name, value)
        #   @example
        #     attribute :speed, :slow
        #     def test_my_slow_method
        #       self[:speed] # => :slow
        #     end
        #
        #   @param [Object] name the attribute name
        #   @param [Object] value the attribute value
        #   @return [void]
        #
        # @overload attribute(name, value, *method_names)
        #   @example
        #     def test_my_slow_method1
        #       self[:speed] # => :slow
        #     end
        #
        #     attribute :speed, :slow, :test_my_slow_method1, :test_my_slow_method2
        #
        #     def test_my_slow_method2
        #       self[:speed] # => :slow
        #     end
        #
        #   @param [Object] name the attribute name
        #   @param [Object] value the attribute value
        #   @param [Array<Symbol, String>] method_names the test method names set the attribute
        #   @return [void]
        #
        # @overload attribute(name, value, options)
        #   @example
        #     attribute :speed, :slow, keep: true
        #     def test_my_slow_method1
        #       self[:speed] # => :slow
        #     end
        #
        #     def test_my_slow_method2
        #       self[:speed] # => :slow
        #     end
        #
        #   @param [Object] name the attribute name
        #   @param [Object] value the attribute value
        #   @option options [Boolean] :keep whether or not to set attribute to following test methods
        #   @return [void]
        #
        # @overload attribute(name, value, options, *method_names)
        #   @example
        #     def test_my_slow_method1
        #       self[:speed] # => :slow
        #     end
        #
        #     # There are no valid options for now.
        #     attribute :speed, :slow, {}, :test_my_slow_method1
        #
        #     def test_my_slow_method2
        #       self[:speed] # => nil
        #     end
        #
        #   @param [Object] name the attribute name
        #   @param [Object] value the attribute value
        #   @param [Hash] options ignored
        #   @param [Array<Symbol, String>] method_names the test method names set the attribute
        #   @return [void]
        def attribute(name, value, options={}, *method_names)
          unless options.is_a?(Hash)
            method_names << options
            options = {}
          end
          if method_names.empty?
            current_attributes[name] = options.merge(:value => value)
          else
            method_names.each do |method_name|
              set_attributes(method_name, {name => value})
            end
          end
        end

        def current_attributes
          @current_attributes ||= StringifyKeyHash.new
        end

        def current_attribute(name)
          current_attributes[name] || StringifyKeyHash.new
        end

        def attributes_table
          @attributes_table ||= StringifyKeyHash.new
          super.merge(@attributes_table)
        end

        def set_attributes(method_name, new_attributes)
          return if new_attributes.empty?
          @attributes_table ||= StringifyKeyHash.new
          @attributes_table[method_name] ||= StringifyKeyHash.new
          current_attributes = @attributes_table[method_name]
          new_attributes.each do |key, value|
            observers = attribute_observers(key) || []
            observers.each do |observer|
              observer.call(self,
                            StringifyKeyHash.stringify(key),
                            (attributes(method_name) || {})[key],
                            value,
                            method_name)
            end
            current_attributes[key] = value
          end
        end

        def attributes(method_name)
          attributes = attributes_table[method_name]
          ancestors.each do |ancestor|
            next if ancestor == self
            if ancestor.is_a?(Class) and ancestor < Test::Unit::Attribute
              parent_attributes = ancestor.attributes(method_name)
              if attributes
                attributes = (parent_attributes || {}).merge(attributes)
              else
                attributes = parent_attributes
              end
              break
            end
          end
          attributes || StringifyKeyHash.new
        end

        def find_attribute(method_name, name, options={})
          recursive_p = options[:recursive]
          recursive_p = true if recursive_p.nil?

          @attributes_table ||= StringifyKeyHash.new
          if @attributes_table.key?(method_name)
            attributes = @attributes_table[method_name]
            if attributes.key?(name)
              return attributes[name]
            end
          end

          return nil unless recursive_p
          return nil if self == TestCase

          @cached_parent_test_case ||= ancestors.find do |ancestor|
            ancestor != self and
              ancestor.is_a?(Class) and
              ancestor < Test::Unit::Attribute
          end

          @cached_parent_test_case.find_attribute(method_name, name, options)
        end

        @@attribute_observers = StringifyKeyHash.new
        def register_attribute_observer(attribute_name, observer=nil, &block)
          observer ||= Proc.new(&block)
          @@attribute_observers[attribute_name] ||= []
          @@attribute_observers[attribute_name] << observer
        end

        def attribute_observers(attribute_name)
          @@attribute_observers[attribute_name]
        end
      end

      def attributes
        self.class.attributes(@method_name) || StringifyKeyHash.new
      end

      def [](name)
        self.class.find_attribute(@method_name, name)
      end
    end
  end
end
