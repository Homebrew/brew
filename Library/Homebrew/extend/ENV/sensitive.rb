# typed: strict
# frozen_string_literal: true

require "env_config"

module EnvSensitive
  extend T::Helpers

  requires_ancestor { Sorbet::Private::Static::ENVClass }

  sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
  def sensitive?(key)
    key.match?(/(cookie|key|token|password|passphrase|auth)/i)
  end

  sig { returns(T::Hash[String, String]) }
  def sensitive_environment
    select { |key, _| sensitive?(key) }
  end

  sig { params(except: T::Array[String], block: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
  def clear_sensitive_environment!(except: [], &block)
    unless block
      each_key { |key| delete key if sensitive?(key) && except.exclude?(key) }
      return
    end

    old_env = to_hash.dup
    begin
      clear_sensitive_environment!(except:)
      yield
    ensure
      replace(old_env)
    end
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def clear_sensitive_environment_for_eval!(&block)
    clear_sensitive_environment!(except: ["HOMEBREW_GITHUB_API_TOKEN"], &block)
  end
end

ENV.extend(EnvSensitive)
