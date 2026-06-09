# typed: strict
# frozen_string_literal: true

require "json"
require "tap"
require "trust"
require "utils"

module Homebrew
  module Bundle
    module Trust
      extend Homebrew::Trust::Read

      sig { void }
      def self.reset!
        @trust_data = T.let(nil, T.nilable(T::Hash[String, T::Array[String]]))
      end

      sig { override.params(type: Symbol).returns(T::Array[String]) }
      def self.trusted_entries(type)
        return Homebrew::Trust.trusted_entries(type) if Homebrew::EnvConfig.force_brew_wrapper.blank?

        trust_data.fetch(Utils.pluralize(type.to_s, 2), [])
      end

      sig { params(type: Symbol, name: String).returns(T::Boolean) }
      def self.trust!(type, name)
        newly_trusted = Homebrew::Trust.trust!(type, name)

        # In wrapper mode, save the trust to both trust stores.
        return newly_trusted if Homebrew::EnvConfig.force_brew_wrapper.blank?

        already_trusted = trusted?(type, name)
        Utils.safe_popen_read(HOMEBREW_BREW_FILE, "trust", "--#{type}", name)
        reset!

        !already_trusted || newly_trusted
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      private_class_method def self.trust_data
        @trust_data ||= T.let(begin
          data = JSON.parse(Utils.safe_popen_read(HOMEBREW_BREW_FILE, "trust", "--json=v1"))
          raise "Unexpected `brew trust --json=v1` output: #{data.inspect}" unless data.is_a?(Hash)

          data
        end, T.nilable(T::Hash[String, T::Array[String]]))
      end
    end
  end
end
