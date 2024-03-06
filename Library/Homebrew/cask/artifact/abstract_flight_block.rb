# typed: true
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Abstract superclass for block artifacts.
    class AbstractFlightBlock < AbstractArtifact
      def self.dsl_key
        super.to_s.sub(/_block$/, "").to_sym
      end

      def self.uninstall_dsl_key
        dsl_key.to_s.prepend("uninstall_").to_sym
      end

      attr_reader :directives

      def initialize(cask, **directives)
        super(cask)
        @directives = directives
      end

      def install_phase(**)
        abstract_phase(self.class.dsl_key)
      end

      def uninstall_phase(**)
        abstract_phase(self.class.uninstall_dsl_key)
      end

      def summarize
        directives.keys.map(&:to_s).join(", ")
      end

      private

      def class_for_dsl_key(dsl_key)
        namespace = self.class.name.to_s.sub(/::.*::.*$/, "")
        self.class.const_get("#{namespace}::DSL::#{dsl_key.to_s.split("_").map(&:capitalize).join}")
      end

      def abstract_phase(dsl_key)
        return if (block = directives[dsl_key]).nil?

        class_for_dsl_key(dsl_key).new(cask).instance_eval(&block)
      end
    end
  end
end
