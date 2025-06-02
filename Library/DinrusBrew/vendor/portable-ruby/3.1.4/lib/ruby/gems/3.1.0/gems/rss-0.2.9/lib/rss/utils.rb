# frozen_string_literal: false
module RSS

  ##
  # RSS::Utils is a module that holds various utility functions that are used
  # across many parts of the rest of the RSS library. Like most modules named
  # some variant of 'util', its methods are probably not particularly useful
  # to those who aren't developing the library itself.
  module Utils
    module_function

    # Given a +name+ in a name_with_underscores or a name-with-dashes format,
    # returns the CamelCase version of +name+.
    #
    # If the +name+ is already CamelCased, nothing happens.
    #
    # Examples:
    #
    #   require 'rss/utils'
    #
    #   RSS::Utils.to_class_name("sample_name")
    #   # => "SampleName"
    #   RSS::Utils.to_class_name("with-dashes")
    #   # => "WithDashes"
    #   RSS::Utils.to_class_name("CamelCase")
    #   # => "CamelCase"
    def to_class_name(name)
      name.split(/[_\-]/).collect do |part|
        "#{part[0, 1].upcase}#{part[1..-1]}"
      end.join("")
    end

    # Returns an array of two elements: the filename where the calling method
    # is located, and the line number where it is defined.
    #
    # Takes an optional argument +i+, which specifies how many callers up the
    # stack to look.
    #
    # Examples:
    #
    #   require 'rss/utils'
    #
    #   def foo
    #     p RSS::Utils.get_file_and_line_from_caller
    #     p RSS::Utils.get_file_and_line_from_caller(1)
    #   end
    #
    #   def bar
    #     foo
    #   end
    #
    #   def baz
    #     bar
    #   end
    #
    #   baz
    #   # => ["test.rb", 5]
    #   # => ["test.rb", 9]
    #
    # If +i+ is not given, or is the default value of 0, it attempts to figure
    # out the correct value. This is useful when in combination with
    # instance_eval. For example:
    #
    #   require 'rss/utils'
    #
    #   def foo
    #     p RSS::Utils.get_file_and_line_from_caller(1)
    #   end
    #
    #   def bar
    #     foo
    #   end
    #
    #   instance_eval <<-RUBY, *RSS::Utils.get_file_and_line_from_caller
    #   def baz
    #     bar
    #   end
    #   RUBY
    #
    #   baz
    #
    #   # => ["test.rb", 8]
    def get_file_and_line_from_caller(i=0)
      file, line, = caller[i].split(':')
      line = line.to_i
      line += 1 if i.zero?
      [file, line]
    end

    # Takes a string +s+ with some HTML in it, and escapes '&', '"', '<' and '>', by
    # replacing them with the appropriate entities.
    #
    # This method is also aliased to h, for convenience.
    #
    # Examples:
    #
    #   require 'rss/utils'
    #
    #   RSS::Utils.html_escape("Dungeons & Dragons")
    #   # => "Dungeons &amp; Dragons"
    #   RSS::Utils.h(">_>")
    #   # => "&gt;_&gt;"
    def html_escape(s)
      s.to_s.gsub(/&/, "&amp;").gsub(/\"/, "&quot;").gsub(/>/, "&gt;").gsub(/</, "&lt;")
    end
    alias h html_escape

    # If +value+ is an instance of class +klass+, return it, else
    # create a new instance of +klass+ with value +value+.
    def new_with_value_if_need(klass, value)
      if value.is_a?(klass)
        value
      else
        klass.new(value)
      end
    end

    # This method is used inside of several different objects to determine
    # if special behavior is needed in the constructor.
    #
    # Special behavior is needed if the array passed in as +args+ has
    # +true+ or +false+ as its value, and if the second element of +args+
    # is a hash.
    def element_initialize_arguments?(args)
      [true, false].include?(args[0]) and args[1].is_a?(Hash)
    end

    module ExplicitCleanOther
      module_function
      def parse(value)
        if [true, false, nil].include?(value)
          value
        else
          case value.to_s
          when /\Aexplicit|yes|true\z/i
            true
          when /\Aclean|no|false\z/i
            false
          else
            nil
          end
        end
      end
    end

    module YesOther
      module_function
      def parse(value)
        if [true, false].include?(value)
          value
        else
          /\Ayes\z/i.match(value.to_s) ? true : false
        end
      end
    end

    module CSV
      module_function
      def parse(value, &block)
        if value.is_a?(String)
          value = value.strip.split(/\s*,\s*/)
          value = value.collect(&block) if block_given?
          value
        else
          value
        end
      end
    end

    module InheritedReader
      def inherited_reader(constant_name)
        base_class = inherited_base
        result = base_class.const_get(constant_name)
        found_base_class = false
        ancestors.reverse_each do |klass|
          if found_base_class
            if klass.const_defined?(constant_name)
              result = yield(result, klass.const_get(constant_name))
            end
          else
            found_base_class = klass == base_class
          end
        end
        result
      end

      def inherited_array_reader(constant_name)
        inherited_reader(constant_name) do |result, current|
          current + result
        end
      end

      def inherited_hash_reader(constant_name)
        inherited_reader(constant_name) do |result, current|
          result.merge(current)
        end
      end
    end
  end
end
