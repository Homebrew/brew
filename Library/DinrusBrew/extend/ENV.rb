# typed: strict
# frozen_string_literal: true

require "hardware"
require "diagnostic"
require "extend/ENV/shared"
require "extend/ENV/std"
require "extend/ENV/super"

module Kernel
  sig { params(env: T.nilable(String)).returns(T::Boolean) }
  def superenv?(env)
    return false if env == "std"

    !Superenv.bin.nil?
  end
  private :superenv?
end

# <!-- vale off -->
# @!parse
#   # `ENV` is not actually a class, but this makes YARD happy
#   # @see https://rubydoc.info/stdlib/core/ENV
#   #   <code>ENV</code> core documentation
#   # @see Superenv
#   # @see Stdenv
#   class ENV; end
# <!-- vale on -->

module EnvActivation
  sig { params(env: T.nilable(String)).void }
  def activate_extensions!(env: nil)
    if superenv?(env)
      extend(Superenv)
    else
      extend(Stdenv)
    end
  end

  sig {
    params(
      env:           T.nilable(String),
      cc:            T.nilable(String),
      build_bottle:  T::Boolean,
      bottle_arch:   T.nilable(String),
      debug_symbols: T.nilable(T::Boolean),
      _block:        T.proc.returns(T.untyped),
    ).returns(T.untyped)
  }
  def with_build_environment(env: nil, cc: nil, build_bottle: false, bottle_arch: nil, debug_symbols: false, &_block)
    old_env = to_hash.dup
    tmp_env = to_hash.dup.extend(EnvActivation)
    T.cast(tmp_env, EnvActivation).activate_extensions!(env:)
    T.cast(tmp_env, T.any(Superenv, Stdenv))
     .setup_build_environment(cc:, build_bottle:, bottle_arch:,
                              debug_symbols:)
    replace(tmp_env)

    begin
      yield
    ensure
      replace(old_env)
    end
  end

  sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
  def sensitive?(key)
    key.match?(/(cookie|key|token|password|passphrase)/i)
  end

  sig { returns(T::Hash[String, String]) }
  def sensitive_environment
    select { |key, _| sensitive?(key) }
  end

  sig { void }
  def clear_sensitive_environment!
    each_key { |key| delete key if sensitive?(key) }
  end
end

ENV.extend(EnvActivation)
