require 'bindata/dsl'
require 'bindata/struct'

module BinData
  # A Record is a declarative wrapper around Struct.
  #
  # See +Struct+ for more info.
  class Record < BinData::Struct
    extend DSLMixin

    unregister_self
    dsl_parser    :struct
    arg_processor :record
  end

  class RecordArgProcessor < StructArgProcessor
    include MultiFieldArgSeparator

    def sanitize_parameters!(obj_class, params)
      super(obj_class, params.merge!(obj_class.dsl_params))
    end
  end
end
