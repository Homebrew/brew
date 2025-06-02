# frozen_string_literal: true

module Bundler
  class EnvironmentPreserver
    INTENTIONALLY_NIL = "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL"
    BUNDLER_KEYS = %w[
      BUNDLE_BIN_PATH
      BUNDLE_GEMFILE
      BUNDLER_VERSION
      BUNDLER_SETUP
      GEM_HOME
      GEM_PATH
      MANPATH
      PATH
      RB_USER_INSTALL
      RUBYLIB
      RUBYOPT
    ].map(&:freeze).freeze
    BUNDLER_PREFIX = "BUNDLER_ORIG_"

    def self.from_env
      new(ENV.to_hash, BUNDLER_KEYS)
    end

    # @param env [Hash]
    # @param keys [Array<String>]
    def initialize(env, keys)
      @original = env
      @keys = keys
      @prefix = BUNDLER_PREFIX
    end

    # Replaces `ENV` with the bundler environment variables backed up
    def replace_with_backup
      ENV.replace(backup)
    end

    # @return [Hash]
    def backup
      env = @original.clone
      @keys.each do |key|
        value = env[key]
        if !value.nil?
          env[@prefix + key] ||= value
        else
          env[@prefix + key] ||= INTENTIONALLY_NIL
        end
      end
      env
    end

    # @return [Hash]
    def restore
      env = @original.clone
      @keys.each do |key|
        value_original = env[@prefix + key]
        next if value_original.nil?
        if value_original == INTENTIONALLY_NIL
          env.delete(key)
        else
          env[key] = value_original
        end
        env.delete(@prefix + key)
      end
      env
    end
  end
end
