class Reline::KeyActor::Composite
  def initialize(key_actors)
    @key_actors = key_actors
  end

  def matching?(key)
    @key_actors.any? { |key_actor| key_actor.matching?(key) }
  end

  def get(key)
    @key_actors.each do |key_actor|
      func = key_actor.get(key)
      return func if func
    end
    nil
  end
end
