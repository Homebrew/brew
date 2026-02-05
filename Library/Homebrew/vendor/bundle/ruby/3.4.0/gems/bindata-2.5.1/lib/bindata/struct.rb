require 'bindata/base'
require 'bindata/delayed_io'

module BinData
  class Base
    optional_parameter :onlyif, :byte_align  # Used by Struct
  end

  # A Struct is an ordered collection of named data objects.
  #
  #    require 'bindata'
  #
  #    class Tuple < BinData::Record
  #      int8  :x
  #      int8  :y
  #      int8  :z
  #    end
  #
  #    obj = BinData::Struct.new(hide: :a,
  #                              fields: [ [:int32le, :a],
  #                                        [:int16le, :b],
  #                                        [:tuple, :s] ])
  #    obj.field_names   =># [:b, :s]
  #
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # <tt>:fields</tt>::   An array specifying the fields for this struct.
  #                      Each element of the array is of the form [type, name,
  #                      params].  Type is a symbol representing a registered
  #                      type.  Name is the name of this field.  Params is an
  #                      optional hash of parameters to pass to this field
  #                      when instantiating it.  If name is "" or nil, then
  #                      that field is anonymous and behaves as a hidden field.
  # <tt>:hide</tt>::     A list of the names of fields that are to be hidden
  #                      from the outside world.  Hidden fields don't appear
  #                      in #snapshot or #field_names but are still accessible
  #                      by name.
  # <tt>:endian</tt>::   Either :little or :big.  This specifies the default
  #                      endian of any numerics in this struct, or in any
  #                      nested data objects.
  # <tt>:search_prefix</tt>::  Allows abbreviated type names.  If a type is
  #                            unrecognised, then each prefix is applied until
  #                            a match is found.
  #
  # == Field Parameters
  #
  # Fields may have have extra parameters as listed below:
  #
  # [<tt>:onlyif</tt>]     Used to indicate a data object is optional.
  #                        if +false+, this object will not be included in any
  #                        calls to #read, #write, #num_bytes or #snapshot.
  # [<tt>:byte_align</tt>] This field's rel_offset must be a multiple of
  #                        <tt>:byte_align</tt>.
  class Struct < BinData::Base
    arg_processor :struct

    mandatory_parameter :fields
    optional_parameters :endian, :search_prefix, :hide

    # These reserved words may not be used as field names
    RESERVED =
      Hash[*
        (Hash.instance_methods +
         %w[alias and begin break case class def defined do else elsif
            end ensure false for if in module next nil not or redo
            rescue retry return self super then true undef unless until
            when while yield] +
         %w[array element index value] +
         %w[type initial_length read_until] +
         %w[fields endian search_prefix hide onlyif byte_align] +
         %w[choices selection copy_on_change] +
         %w[read_abs_offset struct_params])
        .collect(&:to_sym)
        .uniq.collect { |key| [key, true] }
        .flatten
      ]

    def initialize_shared_instance
      fields = get_parameter(:fields)
      @field_names = fields.field_names.freeze
      extend ByteAlignPlugin if fields.any_field_has_parameter?(:byte_align)
      define_field_accessors
      super
    end

    def initialize_instance
      @field_objs = []
    end

    def clear # :nodoc:
      @field_objs.each { |f| f.nil? || f.clear }
    end

    def clear? # :nodoc:
      @field_objs.all? { |f| f.nil? || f.clear? }
    end

    def assign(val)
      clear
      assign_fields(val)
    end

    def snapshot
      snapshot = Snapshot.new
      field_names.each do |name|
        obj = find_obj_for_name(name)
        snapshot[name] = obj.snapshot if include_obj?(obj)
      end
      snapshot
    end

    # Returns a list of the names of all fields accessible through this
    # object.  +include_hidden+ specifies whether to include hidden names
    # in the listing.
    def field_names(include_hidden = false)
      if include_hidden
        @field_names.compact
      else
        hidden = get_parameter(:hide) || []
        @field_names.compact - hidden
      end
    end

    def debug_name_of(child) # :nodoc:
      field_name = @field_names[find_index_of(child)]
      "#{debug_name}.#{field_name}"
    end

    def offset_of(child) # :nodoc:
      instantiate_all_objs
      sum = sum_num_bytes_below_index(find_index_of(child))
      child.bit_aligned? ? sum.floor : sum.ceil
    end

    def do_read(io) # :nodoc:
      instantiate_all_objs
      @field_objs.each { |f| f.do_read(io) if include_obj_for_io?(f) }
    end

    def do_write(io) # :nodoc:
      instantiate_all_objs
      @field_objs.each { |f| f.do_write(io) if include_obj_for_io?(f) }
    end

    def do_num_bytes # :nodoc:
      instantiate_all_objs
      sum_num_bytes_for_all_fields
    end

    def [](key)
      find_obj_for_name(key)
    end

    def []=(key, value)
      find_obj_for_name(key)&.assign(value)
    end

    def key?(key)
      @field_names.index(base_field_name(key))
    end

    # Calls the given block for each field_name-field_obj pair.
    #
    # Does not include anonymous or hidden fields unless
    # +include_all+ is true.
    def each_pair(include_all = false)
      instantiate_all_objs

      pairs = @field_names.zip(@field_objs).select do |name, _obj|
        name || include_all
      end

      if block_given?
        pairs.each { |el| yield(el) }
      else
        pairs.each
      end
    end

    #---------------
    private

    def define_field_accessors
      get_parameter(:fields).each_with_index do |field, i|
        name = field.name_as_sym
        define_field_accessors_for(name, i) if name
      end
    end

    def define_field_accessors_for(name, index)
      define_singleton_method(name) do
        instantiate_obj_at(index) if @field_objs[index].nil?
        @field_objs[index]
      end
      define_singleton_method("#{name}=") do |*vals|
        instantiate_obj_at(index) if @field_objs[index].nil?
        @field_objs[index].assign(*vals)
      end
      define_singleton_method("#{name}?") do
        instantiate_obj_at(index) if @field_objs[index].nil?
        include_obj?(@field_objs[index])
      end
    end

    def find_index_of(obj)
      @field_objs.index { |el| el.equal?(obj) }
    end

    def find_obj_for_name(name)
      index = @field_names.index(base_field_name(name))
      if index
        instantiate_obj_at(index)
        @field_objs[index]
      end
    end

    def base_field_name(name)
      name.to_s.sub(/(=|\?)\z/, "").to_sym
    end

    def instantiate_all_objs
      @field_names.each_index { |i| instantiate_obj_at(i) }
    end

    def instantiate_obj_at(index)
      if @field_objs[index].nil?
        field = get_parameter(:fields)[index]
        @field_objs[index] = field.instantiate(nil, self)
      end
    end

    def assign_fields(val)
      src = as_stringified_hash(val)

      @field_names.compact.each do |name|
        obj = find_obj_for_name(name)
        if obj && src.key?(name)
          obj.assign(src[name])
        end
      end
    end

    def as_stringified_hash(val)
      if BinData::Struct === val
        val
      elsif val.nil?
        {}
      else
        hash = Snapshot.new
        val.each_pair { |k, v| hash[k] = v }
        hash
      end
    end

    def sum_num_bytes_for_all_fields
      sum_num_bytes_below_index(@field_objs.length)
    end

    def sum_num_bytes_below_index(index)
      (0...index).inject(0) do |sum, i|
        obj = @field_objs[i]
        if include_obj?(obj)
          nbytes = obj.do_num_bytes
          (nbytes.is_a?(Integer) ? sum.ceil : sum) + nbytes
        else
          sum
        end
      end
    end

    def include_obj_for_io?(obj)
      # Used by #do_read and #do_write, to ensure the stream is passed to
      # DelayedIO objects for delayed processing.
      include_obj?(obj) || DelayedIO === obj
    end

    def include_obj?(obj)
      !obj.has_parameter?(:onlyif) || obj.eval_parameter(:onlyif)
    end

    # A hash that can be accessed via attributes.
    class Snapshot < ::Hash # :nodoc:
      def []=(key, value)
        super unless value.nil?
      end

      def respond_to_missing?(symbol, include_all = false)
        key?(symbol) || super
      end

      def method_missing(symbol, *args)
        key?(symbol) ? self[symbol] : super
      end
    end

    # Align fields to a multiple of :byte_align
    module ByteAlignPlugin
      def do_read(io)
        offset = 0
        instantiate_all_objs
        @field_objs.each do |f|
          next unless include_obj?(f)

          if align_obj?(f)
            nbytes = bytes_to_align(f, offset.ceil)
            offset = offset.ceil + nbytes
            io.readbytes(nbytes)
          end

          f.do_read(io)
          nbytes = f.do_num_bytes
          offset = (nbytes.is_a?(Integer) ? offset.ceil : offset) + nbytes
        end
      end

      def do_write(io)
        offset = 0
        instantiate_all_objs
        @field_objs.each do |f|
          next unless include_obj?(f)

          if align_obj?(f)
            nbytes = bytes_to_align(f, offset.ceil)
            offset = offset.ceil + nbytes
            io.writebytes("\x00" * nbytes)
          end

          f.do_write(io)
          nbytes = f.do_num_bytes
          offset = (nbytes.is_a?(Integer) ? offset.ceil : offset) + nbytes
        end
      end

      def sum_num_bytes_below_index(index)
        sum = 0
        @field_objs.each_with_index do |obj, i|
          next unless include_obj?(obj)

          if align_obj?(obj)
            sum = sum.ceil + bytes_to_align(obj, sum.ceil)
          end

          break if i >= index

          nbytes = obj.do_num_bytes
          sum = (nbytes.is_a?(Integer) ? sum.ceil : sum) + nbytes
        end

        sum
      end

      def bytes_to_align(obj, rel_offset)
        align = obj.eval_parameter(:byte_align)
        (align - (rel_offset % align)) % align
      end

      def align_obj?(obj)
        obj.has_parameter?(:byte_align)
      end
    end
  end

  class StructArgProcessor < BaseArgProcessor
    def sanitize_parameters!(obj_class, params)
      sanitize_endian(params)
      sanitize_search_prefix(params)
      sanitize_fields(obj_class, params)
      sanitize_hide(params)
    end

    #-------------
    private

    def sanitize_endian(params)
      params.sanitize_endian(:endian)
    end

    def sanitize_search_prefix(params)
      params.sanitize(:search_prefix) do |sprefix|
        search_prefix = Array(sprefix).collect do |prefix|
          prefix.to_s.chomp("_")
        end

        search_prefix - [""]
      end
    end

    def sanitize_fields(obj_class, params)
      params.sanitize_fields(:fields) do |fields, sanitized_fields|
        fields.each do |ftype, fname, fparams|
          sanitized_fields.add_field(ftype, fname, fparams)
        end

        field_names = sanitized_field_names(sanitized_fields)
        ensure_field_names_are_valid(obj_class, field_names)
      end
    end

    def sanitize_hide(params)
      params.sanitize(:hide) do |hidden|
        field_names  = sanitized_field_names(params[:fields])
        hfield_names = hidden_field_names(hidden)

        hfield_names & field_names
      end
    end

    def sanitized_field_names(sanitized_fields)
      sanitized_fields.field_names.compact
    end

    def hidden_field_names(hidden)
      (hidden || []).collect(&:to_sym)
    end

    def ensure_field_names_are_valid(obj_class, field_names)
      reserved_names = BinData::Struct::RESERVED

      field_names.each do |name|
        if obj_class.method_defined?(name)
          raise NameError.new("Rename field '#{name}' in #{obj_class}, " \
                              "as it shadows an existing method.", name)
        end
        if reserved_names.include?(name)
          raise NameError.new("Rename field '#{name}' in #{obj_class}, " \
                              "as it is a reserved name.", name)
        end
        if field_names.count(name) != 1
          raise NameError.new("field '#{name}' in #{obj_class}, " \
                              "is defined multiple times.", name)
        end
      end
    end
  end
end
