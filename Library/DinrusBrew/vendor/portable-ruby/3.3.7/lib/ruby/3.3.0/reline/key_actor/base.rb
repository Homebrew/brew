class Reline::KeyActor::Base
  def initialize(mapping = [])
    @mapping = mapping
    @matching_bytes = {}
    @key_bindings = {}
  end

  def get_method(key)
    @mapping[key]
  end

  def add(key, func)
    (1...key.size).each do |size|
      @matching_bytes[key.take(size)] = true
    end
    @key_bindings[key] = func
  end

  def matching?(key)
    @matching_bytes[key]
  end

  def get(key)
    @key_bindings[key]
  end

  def clear
    @matching_bytes.clear
    @key_bindings.clear
  end
end
