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

      sig {
        params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        command: SystemCommand)
        abstract_phase(self.class.dsl_key)
      end

      sig {
        params(
          skip:      T::Boolean,
          force:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def uninstall_phase(skip: false, force: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, command: SystemCommand)
        abstract_phase(self.class.uninstall_dsl_key)
      end

      sig { override.returns(String) }
      def summarize
        directives.keys.join(", ")
      end

      sig { params(dsl_key: Symbol).returns(T::Class[::Cask::DSL::Base]) }
      def self.class_for_dsl_key(dsl_key)
        namespace = name.to_s.sub(/::.*::.*$/, "")
        # The DSL class name is derived dynamically from the flight block's key.
        # rubocop:disable Sorbet/ConstantsFromStrings
        const_get("#{namespace}::DSL::#{dsl_key.to_s.split("_").map(&:capitalize).join}")
        # rubocop:enable Sorbet/ConstantsFromStrings
      end

      private

      sig { params(dsl_key: Symbol).void }
      def abstract_phase(dsl_key)
        return if (block = directives[dsl_key]).nil?

        self.class.class_for_dsl_key(dsl_key).new(cask).instance_eval(&T.cast(block, T.proc.returns(T.anything)))
      end
    end
  end
end
