class Reline::KeyActor::Base
  MAPPING = Array.new(256)

  def get_method(key)
    self.class::MAPPING[key]
  end

  def initialize
    @default_key_bindings = {}
  end

  def default_key_bindings
    @default_key_bindings
  end

  def reset_default_key_bindings
    @default_key_bindings.clear
  end
end
