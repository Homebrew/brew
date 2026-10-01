# typed: strict
# frozen_string_literal: true

require "env_config"
require "context"

module EnvSensitive
  extend T::Helpers

  requires_ancestor { Sorbet::Private::Static::ENVClass }

  # `bin/brew` re-execs with only `HOMEBREW_*` variables (plus a fixed
  # non-secret allowlist) in the environment, so every secret reaching
  # formula/cask evaluation is `HOMEBREW_*`. These markers wrap a deferred
  # secret name interpolated into the DSL in place of the real value; the real
  # value is swapped back in at download time by `expand_deferred_environment`.
  DEFERRED_PLACEHOLDER_PREFIX = "{{HOMEBREW_DEFERRED_ENV:"
  DEFERRED_PLACEHOLDER_SUFFIX = "}}"

  sig { params(key: T.any(String, Symbol)).returns(T::Boolean) }
  def sensitive?(key)
    key.match?(/(cookie|key|token|password|passphrase|auth)/i)
  end

  sig { returns(T::Hash[String, String]) }
  def sensitive_environment
    select { |key, _| sensitive?(key) }
  end

  sig {
    params(
      except: T::Array[String],
      defer:  T::Boolean,
      block:  T.nilable(T.proc.returns(T.untyped)),
    ).returns(T.untyped)
  }
  def clear_sensitive_environment!(except: [], defer: false, &block)
    unless block
      each_key do |key|
        next unless sensitive?(key)
        next if except.include?(key)

        if defer
          self[key] = "#{DEFERRED_PLACEHOLDER_PREFIX}#{key}#{DEFERRED_PLACEHOLDER_SUFFIX}"
        else
          delete key
        end
      end
      return
    end

    old_env = to_hash.dup
    begin
      clear_sensitive_environment!(except:, defer:)
      yield
    ensure
      replace(old_env)
    end
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def clear_sensitive_environment_for_eval!(&block)
    clear_sensitive_environment!(except: ["HOMEBREW_GITHUB_API_TOKEN"], defer: true, &block)
  end

  # Only the download path (a URL's `header:`/specs) calls this, so a masked
  # secret is resolved to its real value solely when fetching, never elsewhere
  # in the DSL.
  sig { params(value: String).returns(String) }
  def expand_deferred_environment(value)
    return value unless value.include?(DEFERRED_PLACEHOLDER_PREFIX)
    return value unless Context.current.deferred_environment_expansion?

    prefix = Regexp.escape(DEFERRED_PLACEHOLDER_PREFIX)
    suffix = Regexp.escape(DEFERRED_PLACEHOLDER_SUFFIX)
    value.gsub(/#{prefix}(HOMEBREW_\w+)#{suffix}/) do
      name = Regexp.last_match(1)
      name ? fetch(name, "") : ""
    end
  end
end

ENV.extend(EnvSensitive)
