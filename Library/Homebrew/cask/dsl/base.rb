# typed: true
# frozen_string_literal: true

require "cask/utils"
require "extend/on_system"

module Cask
  class DSL
    # Superclass for all stanzas which take a block.
    class Base
      extend Forwardable

      def initialize(cask, command = SystemCommand)
        @cask = cask
        @command = command
      end

      def_delegators :@cask, :token, :version, :caskroom_path, :staged_path, :appdir, :language, :arch

      def system_command(executable, **options)
        @command.run!(executable, **options)
      end

      # No need to define it as it's the default/superclass implementation.
      # rubocop:disable Style/MissingRespondToMissing
      def method_missing(method, *)
        if method
          underscored_class = T.must(self.class.name).gsub(/([[:lower:]])([[:upper:]][[:lower:]])/, '\1_\2').downcase
          section = underscored_class.split("::").last
          Utils.method_missing_message(method, @cask.to_s, section)
          nil
        else
          super
        end
      end
      # rubocop:enable Style/MissingRespondToMissing
    end
  end
end
