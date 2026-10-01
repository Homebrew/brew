# typed: true
# frozen_string_literal: true

require_relative "testball"

class TestballFetch < Testball
  Cache = type_template { { fixed: T::Hash[Symbol, T.untyped] } }

  def initialize(name = "testball_fetch", path = Pathname.new(__FILE__).expand_path, spec = :stable,
                 alias_path: nil, tap: nil, force_bottle: false)
    super
  end

  def fetch
    Pathname("fetched").write "fetched"
  end

  def install
    prefix.install "fetched"
    super
  end
end
