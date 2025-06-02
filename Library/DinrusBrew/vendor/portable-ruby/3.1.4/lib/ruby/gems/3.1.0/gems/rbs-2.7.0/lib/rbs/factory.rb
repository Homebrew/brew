# frozen_string_literal: true

module RBS
  class Factory
    def type_name(string)
      absolute = string.start_with?("::")

      *path, name = string.delete_prefix("::").split("::").map(&:to_sym)

      name or raise

      TypeName.new(
        name: name,
        namespace: Namespace.new(path: path, absolute: absolute)
      )
    end
  end
end
