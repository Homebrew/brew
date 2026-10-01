# typed: strict
# frozen_string_literal: true

# Permanent configuration per {Tap} using `git-config(1)`.
class TapConfig
  sig { returns(Tap) }
  attr_reader :tap

  sig { params(tap: Tap).void }
  def initialize(tap)
    @tap = tap
  end

  sig { params(key: Symbol).returns(T.nilable(T::Boolean)) }
  def [](key)
    return unless tap.git?
    return unless Utils::Git.available?

    case Homebrew::Settings.read(key, repo: tap.path)
    when "true" then true
    when "false" then false
    end
  end

  sig { params(key: Symbol, value: T::Boolean).void }
  def []=(key, value)
    return unless tap.git?
    return unless Utils::Git.available?

    Homebrew::Settings.write key, value.to_s, repo: tap.path
  end

  sig { params(key: Symbol).void }
  def delete(key)
    return unless tap.git?
    return unless Utils::Git.available?

    Homebrew::Settings.delete key, repo: tap.path
  end
end
