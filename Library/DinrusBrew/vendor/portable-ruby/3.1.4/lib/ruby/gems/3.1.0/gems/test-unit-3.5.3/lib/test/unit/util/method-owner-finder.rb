module Test
  module Unit
    module Util
      module MethodOwnerFinder
        module_function
        def find(object, method_name)
          method = object.method(method_name)
          return method.owner if method.respond_to?(:owner)

          if /\((.+?)\)\#/ =~ method.to_s
            owner_name = $1
            if /\A#</ =~ owner_name
              ObjectSpace.each_object(Module) do |mod|
                return mod if mod.to_s == owner_name
              end
            else
              owner_name.split(/::/).inject(Object) do |parent, name|
                parent.const_get(name)
              end
            end
          else
            object.class
          end
        end
      end
    end
  end
end
