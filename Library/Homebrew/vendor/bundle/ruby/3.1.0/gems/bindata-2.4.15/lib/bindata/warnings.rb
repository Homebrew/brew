module BinData
  class Base
    # Don't override initialize.  If you are defining a new kind of datatype
    # (list, array, choice etc) then put your initialization code in
    # #initialize_instance.  BinData objects might be initialized as prototypes
    # and your initialization code may not be called.
    #
    # If you're subclassing BinData::Record, you are definitely doing the wrong
    # thing.  Read the documentation on how to use BinData.
    # http://github.com/dmendel/bindata/wiki/Records
    alias_method :initialize_without_warning, :initialize
    def initialize_with_warning(*args)
      owner = method(:initialize).owner
      if owner != BinData::Base
        msg = "Don't override #initialize on #{owner}."
        if %w(BinData::Base BinData::BasePrimitive).include? self.class.superclass.name
          msg += "\nrename #initialize to #initialize_instance."
        end
        fail msg
      end
      initialize_without_warning(*args)
    end
    alias initialize initialize_with_warning

    def initialize_instance(*args)
      unless args.empty?
        fail "#{caller[0]} remove the call to super in #initialize_instance"
      end
    end
  end

  class Struct
    # has_key? is deprecated
    alias has_key? key?
  end
end
