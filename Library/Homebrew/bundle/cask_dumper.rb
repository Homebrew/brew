# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module CaskDumper
      def self.reset!
        @casks = nil
        @cask_names = nil
        @cask_hash = nil
      end

      def self.cask_names
        @cask_names ||= casks.map(&:to_s)
      end

      def self.outdated_cask_names
        return [] unless Bundle.cask_installed?

        casks.select { |c| c.outdated?(greedy: false) }
             .map(&:to_s)
      end

      def self.cask_is_outdated_using_greedy?(cask_name)
        return false unless Bundle.cask_installed?

        cask = casks.find { |c| c.to_s == cask_name }
        return false if cask.nil?

        cask.outdated?(greedy: true)
      end

      def self.dump(describe: false)
        casks.map do |cask|
          description = "# #{cask.desc}\n" if describe && cask.desc.present?
          config = ", args: { #{explicit_s(cask.config)} }" if cask.config.present? && cask.config.explicit.present?
          "#{description}cask \"#{cask}\"#{config}"
        end.join("\n")
      end

      def self.formula_dependencies(cask_list)
        return [] unless Bundle.cask_installed?
        return [] if cask_list.blank?

        casks.flat_map do |cask|
          next unless cask_list.include?(cask.to_s)

          cask.depends_on[:formula]
        end.compact
      end

      private_class_method def self.casks
        return [] unless Bundle.cask_installed?

        require "cask/caskroom"
        @casks ||= Cask::Caskroom.casks
      end

      private_class_method def self.explicit_s(cask_config)
        cask_config.explicit.map do |key, value|
          # inverse of #env - converts :languages config key back to --language flag
          if key == :languages
            key = "language"
            value = cask_config.explicit.fetch(:languages, []).join(",")
          end
          "#{key}: \"#{value.to_s.sub(/^#{Dir.home}/, "~")}\""
        end.join(", ")
      end
    end
  end
end
