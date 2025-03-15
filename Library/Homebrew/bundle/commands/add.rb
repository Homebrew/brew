# typed: true
# frozen_string_literal: true

module Bundle
  module Commands
    module Add
      module_function

      def run(*args, type:, global:, file:)
        Bundle::Adder.add(*args, type:, global:, file:)
      end
    end
  end
end
