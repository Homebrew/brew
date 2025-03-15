# typed: true
# frozen_string_literal: true

module Bundle
  module Commands
    module Remove
      module_function

      def run(*args, type:, global:, file:)
        Bundle::Remover.remove(*args, type:, global:, file:)
      end
    end
  end
end
