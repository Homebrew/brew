# frozen_string_literal: true

class CSV
  # Note: Don't use this class directly. This is an internal class.
  class FieldsConverter
    include Enumerable
    #
    # A CSV::FieldsConverter is a data structure for storing the
    # fields converter properties to be passed as a parameter
    # when parsing a new file (e.g. CSV::Parser.new(@io, parser_options))
    #

    def initialize(options={})
      @converters = []
      @nil_value = options[:nil_value]
      @empty_value = options[:empty_value]
      @empty_value_is_empty_string = (@empty_value == "")
      @accept_nil = options[:accept_nil]
      @builtin_converters_name = options[:builtin_converters_name]
      @need_static_convert = need_static_convert?
    end

    def add_converter(name=nil, &converter)
      if name.nil?  # custom converter
        @converters << converter
      else          # named converter
        combo = builtin_converters[name]
        case combo
        when Array  # combo converter
          combo.each do |sub_name|
            add_converter(sub_name)
          end
        else        # individual named converter
          @converters << combo
        end
      end
    end

    def each(&block)
      @converters.each(&block)
    end

    def empty?
      @converters.empty?
    end

    def convert(fields, headers, lineno, quoted_fields)
      return fields unless need_convert?

      fields.collect.with_index do |field, index|
        if field.nil?
          field = @nil_value
        elsif field.is_a?(String) and field.empty?
          field = @empty_value unless @empty_value_is_empty_string
        end
        @converters.each do |converter|
          break if field.nil? and @accept_nil
          if converter.arity == 1  # straight field converter
            field = converter[field]
          else                     # FieldInfo converter
            if headers
              header = headers[index]
            else
              header = nil
            end
            quoted = quoted_fields[index]
            field = converter[field, FieldInfo.new(index, lineno, header, quoted)]
          end
          break unless field.is_a?(String)  # short-circuit pipeline for speed
        end
        field  # final state of each field, converted or original
      end
    end

    private
    def need_static_convert?
      not (@nil_value.nil? and @empty_value_is_empty_string)
    end

    def need_convert?
      @need_static_convert or
        (not @converters.empty?)
    end

    def builtin_converters
      @builtin_converters ||= ::CSV.const_get(@builtin_converters_name)
    end
  end
end
