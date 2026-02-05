# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Abstract superclass for block artifacts.
    class AbstractFlightBlock < AbstractArtifact
      sig { override.returns(Symbol) }
      def self.dsl_key
        super.to_s.sub(/_block$/, "").to_sym
      end

      sig { returns(Symbol) }
      def self.uninstall_dsl_key
        :"uninstall_#{dsl_key}"
      end

      sig { returns(T::Hash[Symbol, DirectivesType]) }
      attr_reader :directives

      sig { params(cask: Cask, directives: DirectivesType).void }
      def initialize(cask, **directives)
        super(cask)
        @directives = directives
      end

      sig { params(_options: T.anything).void }
      def install_phase(**_options)
        abstract_phase(self.class.dsl_key)
      end

      sig { params(_options: T.anything).void }
      def uninstall_phase(**_options)
        abstract_phase(self.class.uninstall_dsl_key)
      end

      sig { override.returns(String) }
      def summarize
        directives.keys.map(&:to_s).join(", ")
      end

      private

      sig { params(dsl_key: Symbol).returns(T::Class[::Cask::DSL::Base]) }
      def class_for_dsl_key(dsl_key)
        namespace = self.class.name.to_s.sub(/::.*::.*$/, "")
        self.class.const_get("#{namespace}::DSL::#{dsl_key.to_s.split("_").map(&:capitalize).join}")
      end

      sig { params(dsl_key: Symbol).void }
      def abstract_phase(dsl_key)
        return if (block = directives[dsl_key]).nil?

        class_for_dsl_key(dsl_key).new(cask).instance_eval(&T.cast(block, T.proc.returns(T.anything)))
      end
    end
  end
end
