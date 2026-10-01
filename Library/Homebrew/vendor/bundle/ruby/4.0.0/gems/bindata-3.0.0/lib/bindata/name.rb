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
  # <tt>:namespace</tt>:: The namespace that this object belongs to may be
  #                       set explicitly.  This is only useful when dynamically
  #                       generating types.
  #                       <code><pre>
  #                         BinData::Struct.new(name: :my_struct, namespace: :ns1, fields: ...)
  #                         BinData::Struct.new(name: :my_struct, namespace: :ns2, fields: ...)
  #                         array = BinData::Array.new(namespace: :ns1, type: :my_struct)
  #                       </pre></code>
  module RegisterNamePlugin

    def self.included(base) # :nodoc:
      # +name+ and +namespace+ may be provided explicitly.
      base.optional_parameter :name, :namespace
    end

    def initialize_shared_instance
      if has_parameter?(:name)
        name = get_parameter(:name)
        namespace = get_parameter(:namespace) || ""
        RegisteredClasses.register(namespace, name, self)
      end
      super
    end
  end
end
