module BinData
  # Error raised when unexpected results occur when reading data from IO.
  class ValidityError < StandardError; end

  # All methods provided by the framework are to be implemented or overridden 
  # by subclasses of BinData::Base.
  module Framework
    # Initializes the state of the object.  All instance variables that
    # are used by the object must be initialized here.
    def initialize_instance; end

    # Initialises state that is shared by objects with the same parameters.
    #
    # This should only be used when optimising for performance.  Instance
    # variables set here, and changes to the singleton class will be shared
    # between all objects that are initialized with the same parameters.
    # This method is called only once for a particular set of parameters.
    def initialize_shared_instance; end

    # Returns true if the object has not been changed since creation.
    def clear?
      raise NotImplementedError
    end

    # Assigns the value of +val+ to this data object.  Note that +val+ must
    # always be deep copied to ensure no aliasing problems can occur.
    def assign(val)
      raise NotImplementedError
    end

    # Returns a snapshot of this data object.
    def snapshot
      raise NotImplementedError
    end

    # Returns the debug name of +child+.  This only needs to be implemented
    # by objects that contain child objects.
    def debug_name_of(child) # :nodoc:
      debug_name
    end

    # Returns the offset of +child+.  This only needs to be implemented
    # by objects that contain child objects.
    def offset_of(child) # :nodoc:
      0
    end

    # Is this object aligned on non-byte boundaries?
    def bit_aligned?
      false
    end

    # Reads the data for this data object from +io+.
    def do_read(io) # :nodoc:
      raise NotImplementedError
    end

    # Writes the value for this data to +io+.
    def do_write(io) # :nodoc:
      raise NotImplementedError
    end

    # Returns the number of bytes it will take to write this data.
    def do_num_bytes # :nodoc:
      raise NotImplementedError
    end

    # Set visibility requirements of methods to implement
    public :clear?, :assign, :snapshot, :debug_name_of, :offset_of
    protected :initialize_instance, :initialize_shared_instance
    protected :do_read, :do_write, :do_num_bytes
  end
end
