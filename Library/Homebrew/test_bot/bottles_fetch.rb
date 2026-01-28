# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class BottlesFetch < TestFormulae
      attr_accessor :testing_formulae

      def run!(args:)
        info_header "Testing formulae:"
        puts testing_formulae
        puts

        testing_formulae.each do |formula_name|
          fetch_bottles!(formula_name, args:)
          puts
        end
      end

      private

      def fetch_bottles!(formula_name, args:)
        test_header(:BottlesFetch, method: "fetch_bottles!(#{formula_name})")

        formula = Formula[formula_name]
        return if formula.disabled?

        tags = formula.bottle_specification.collector.tags

        odie "#{formula_name} is missing bottles! Did you mean to use `brew pr-publish`?" if tags.blank?

        tags.each do |tag|
          cleanup_during!(args:)
          test "brew", "fetch", "--retry", "--formulae", "--bottle-tag=#{tag}", formula_name
        end
      end
    end
  end
end
