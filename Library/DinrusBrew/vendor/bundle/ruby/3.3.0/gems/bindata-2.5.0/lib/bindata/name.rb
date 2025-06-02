module BinData
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These parameters are:
  #
  # <tt>:name</tt>:: The name that this object can be referred to may be
  #                  set explicitly.  This is only useful when dynamically
  #                  generating types.
  #                  <code><pre>
  #                    BinData::Struct.new(name: :my_struct, fields: ...)
  #                    array = BinData::Array.new(type: :my_struct)
  #                  </pre></code>
  module RegisterNamePlugin

    def self.included(base) # :nodoc:
      # The registered name may be provided explicitly.
      base.optional_parameter :name
    end

    def initialize_shared_instance
      if has_parameter?(:name)
        RegisteredClasses.register(get_parameter(:name), self)
      end
      super
    end
  end
end
