require 'bindata/base'
require 'bindata/dsl'

module BinData
  # An Array is a list of data objects of the same type.
  #
  #   require 'bindata'
  #
  #   data = "\x03\x04\x05\x06\x07\x08\x09"
  #
  #   obj = BinData::Array.new(type: :int8, initial_length: 6)
  #   obj.read(data) #=> [3, 4, 5, 6, 7, 8]
  #
  #   obj = BinData::Array.new(type: :int8,
  #                            read_until: -> { index == 1 })
  #   obj.read(data) #=> [3, 4]
  #
  #   obj = BinData::Array.new(type: :int8,
  #                            read_until: -> { element >= 6 })
  #   obj.read(data) #=> [3, 4, 5, 6]
  #
  #   obj = BinData::Array.new(type: :int8,
  #           read_until: -> { array[index] + array[index - 1] == 13 })
  #   obj.read(data) #=> [3, 4, 5, 6, 7]
  #
  #   obj = BinData::Array.new(type: :int8, read_until: :eof)
  #   obj.read(data) #=> [3, 4, 5, 6, 7, 8, 9]
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # <tt>:type</tt>::           The symbol representing the data type of the
  #                            array elements.  If the type is to have params
  #                            passed to it, then it should be provided as
  #                            <tt>[type_symbol, hash_params]</tt>.
  # <tt>:initial_length</tt>:: The initial length of the array.
  # <tt>:read_until</tt>::     While reading, elements are read until this
  #                            condition is true.  This is typically used to
  #                            read an array until a sentinel value is found.
  #                            The variables +index+, +element+ and +array+
  #                            are made available to any lambda assigned to
  #                            this parameter.  If the value of this parameter
  #                            is the symbol :eof, then the array will read
  #                            as much data from the stream as possible.
  #
  # Each data object in an array has the variable +index+ made available
  # to any lambda evaluated as a parameter of that data object.
  class Array < BinData::Base
    extend DSLMixin
    include Enumerable

    dsl_parser    :array
    arg_processor :array

    mandatory_parameter :type
    optional_parameters :initial_length, :read_until
    mutually_exclusive_parameters :initial_length, :read_until

    def initialize_shared_instance
      @element_prototype = get_parameter(:type)
      if get_parameter(:read_until) == :eof
        extend ReadUntilEOFPlugin
      elsif has_parameter?(:read_until)
        extend ReadUntilPlugin
      elsif has_parameter?(:initial_length)
        extend InitialLengthPlugin
      end

      super
    end

    def initialize_instance
      @elements = nil
    end

    def clear?
      @elements.nil? || elements.all?(&:clear?)
    end

    def assign(array)
      return if self.equal?(array)  # prevent self assignment
      raise ArgumentError, "can't set a nil value for #{debug_name}" if array.nil?

      @elements = []
      concat(array)
    end

    def snapshot
      elements.collect(&:snapshot)
    end

    def find_index(obj)
      elements.index(obj)
    end
    alias index find_index

    # Returns the first index of +obj+ in self.
    #
    # Uses equal? for the comparator.
    def find_index_of(obj)
      elements.index { |el| el.equal?(obj) }
    end

    def push(*args)
      insert(-1, *args)
      self
    end
    alias << push

    def unshift(*args)
      insert(0, *args)
      self
    end

    def concat(array)
      insert(-1, *array.to_ary)
      self
    end

    def insert(index, *objs)
      extend_array(index - 1)
      abs_index = (index >= 0) ? index : index + 1 + length

      # insert elements before...
      new_elements = objs.map { new_element }
      elements.insert(index, *new_elements)

      # ...assigning values
      objs.each_with_index do |obj, i|
        self[abs_index + i] = obj
      end

      self
    end

    # Returns the element at +index+.
    def [](arg1, arg2 = nil)
      if arg1.respond_to?(:to_int) && arg2.nil?
        slice_index(arg1.to_int)
      elsif arg1.respond_to?(:to_int) && arg2.respond_to?(:to_int)
        slice_start_length(arg1.to_int, arg2.to_int)
      elsif arg1.is_a?(Range) && arg2.nil?
        slice_range(arg1)
      else
        raise TypeError, "can't convert #{arg1} into Integer" unless arg1.respond_to?(:to_int)
        raise TypeError, "can't convert #{arg2} into Integer" unless arg2.respond_to?(:to_int)
      end
    end
    alias slice []

    def slice_index(index)
      extend_array(index)
      at(index)
    end

    def slice_start_length(start, length)
      elements[start, length]
    end

    def slice_range(range)
      elements[range]
    end
    private :slice_index, :slice_start_length, :slice_range

    # Returns the element at +index+.  Unlike +slice+, if +index+ is out
    # of range the array will not be automatically extended.
    def at(index)
      elements[index]
    end

    # Sets the element at +index+.
    def []=(index, value)
      extend_array(index)
      elements[index].assign(value)
    end

    # Returns the first element, or the first +n+ elements, of the array.
    # If the array is empty, the first form returns nil, and the second
    # form returns an empty array.
    def first(n = nil)
      if n.nil? && empty?
        # explicitly return nil as arrays grow automatically
        nil
      elsif n.nil?
        self[0]
      else
        self[0, n]
      end
    end

    # Returns the last element, or the last +n+ elements, of the array.
    # If the array is empty, the first form returns nil, and the second
    # form returns an empty array.
    def last(n = nil)
      if n.nil?
        self[-1]
      else
        n = length if n > length
        self[-n, n]
      end
    end

    def length
      elements.length
    end
    alias size length

    def empty?
      length.zero?
    end

    # Allow this object to be used in array context.
    def to_ary
      collect { |el| el }
    end

    def each
      elements.each { |el| yield el }
    end

    def debug_name_of(child) # :nodoc:
      index = find_index_of(child)
      "#{debug_name}[#{index}]"
    end

    def offset_of(child) # :nodoc:
      index = find_index_of(child)
      sum = sum_num_bytes_below_index(index)

      child.bit_aligned? ? sum.floor : sum.ceil
    end

    def do_write(io) # :nodoc:
      elements.each { |el| el.do_write(io) }
    end

    def do_num_bytes # :nodoc:
      sum_num_bytes_for_all_elements
    end

    #---------------
    private

    def extend_array(max_index)
      max_length = max_index + 1
      while elements.length < max_length
        append_new_element
      end
    end

    def elements
      @elements ||= []
    end

    def append_new_element
      element = new_element
      elements << element
      element
    end

    def new_element
      @element_prototype.instantiate(nil, self)
    end

    def sum_num_bytes_for_all_elements
      sum_num_bytes_below_index(length)
    end

    def sum_num_bytes_below_index(index)
      (0...index).inject(0) do |sum, i|
        nbytes = elements[i].do_num_bytes

        if nbytes.is_a?(Integer)
          sum.ceil + nbytes
        else
          sum + nbytes
        end
      end
    end

    # Logic for the :read_until parameter
    module ReadUntilPlugin
      def do_read(io)
        loop do
          element = append_new_element
          element.do_read(io)
          variables = { index: self.length - 1, element: self.last, array: self }
          break if eval_parameter(:read_until, variables)
        end
      end
    end

    # Logic for the read_until: :eof parameter
    module ReadUntilEOFPlugin
      def do_read(io)
        loop do
          element = append_new_element
          begin
            element.do_read(io)
          rescue EOFError, IOError
            elements.pop
            break
          end
        end
      end
    end

    # Logic for the :initial_length parameter
    module InitialLengthPlugin
      def do_read(io)
        elements.each { |el| el.do_read(io) }
      end

      def elements
        if @elements.nil?
          @elements = []
          eval_parameter(:initial_length).times do
            @elements << new_element
          end
        end

        @elements
      end
    end
  end

  class ArrayArgProcessor < BaseArgProcessor
    def sanitize_parameters!(obj_class, params) # :nodoc:
      # ensure one of :initial_length and :read_until exists
      unless params.has_at_least_one_of?(:initial_length, :read_until)
        params[:initial_length] = 0
      end

      params.warn_replacement_parameter(:length, :initial_length)
      params.warn_replacement_parameter(:read_length, :initial_length)
      params.must_be_integer(:initial_length)

      params.merge!(obj_class.dsl_params)
      params.sanitize_object_prototype(:type)
    end
  end
end
