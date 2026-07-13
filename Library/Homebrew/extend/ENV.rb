# typed: strict
# frozen_string_literal: true

require "hardware"
require "extend/ENV/sensitive"
require "extend/ENV/shared"

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
  include EnvSensitive

  sig { params(env: T.nilable(String)).void }
  def activate_extensions!(env: nil)
    require "extend/ENV/std"
    require "extend/ENV/super"

    if superenv?(env)
      extend(Superenv)
    else
      extend(Stdenv)
    end
  end

  sig {
    type_parameters(:U).params(
      env:           T.nilable(String),
      cc:            T.nilable(String),
      build_bottle:  T::Boolean,
      bottle_arch:   T.nilable(String),
      debug_symbols: T.nilable(T::Boolean),
      _block:        T.proc.returns(T.type_parameter(:U)),
    ).returns(T.type_parameter(:U))
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
end

ENV.extend(EnvActivation)
