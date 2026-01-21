# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module CaskDumper
      sig { void }
      def self.reset!
        @casks = nil
        @cask_names = nil
        @cask_oldnames = nil
      end

      sig { returns(T::Array[String]) }
      def self.cask_names
        @cask_names ||= T.let(casks.map(&:to_s), T.nilable(T::Array[String]))
      end

      sig { returns(T::Array[String]) }
      def self.outdated_cask_names
        return [] unless Bundle.cask_installed?

        casks.select { |c| c.outdated?(greedy: false) }
             .map(&:to_s)
      end

      sig { params(cask_name: String).returns(T::Boolean) }
      def self.cask_is_outdated_using_greedy?(cask_name)
        return false unless Bundle.cask_installed?

        cask = casks.find { |c| c.to_s == cask_name }
        return false if cask.nil?

        cask.outdated?(greedy: true)
      end

      sig { params(describe: T::Boolean).returns(String) }
      def self.dump(describe: false)
        casks.map do |cask|
          description = "# #{cask.desc}\n" if describe && cask.desc.present?
          config = ", args: { #{explicit_s(cask.config)} }" if cask.config.present? && cask.config.explicit.present?
          "#{description}cask \"#{cask.full_name}\"#{config}"
        end.join("\n")
      end

      sig { returns(T::Hash[String, String]) }
      def self.cask_oldnames
        @cask_oldnames ||= T.let(casks.each_with_object({}) do |c, hash|
          oldnames = c.old_tokens
          next if oldnames.blank?

          oldnames.each do |oldname|
            hash[oldname] = c.full_name
            if c.full_name.include? "/" # tap cask
              tap_name = c.full_name.rpartition("/").first
              hash["#{tap_name}/#{oldname}"] = c.full_name
            end
          end
        end, T.nilable(T::Hash[String, String]))
      end

      sig { params(cask_list: T::Array[String]).returns(T::Array[String]) }
      def self.formula_dependencies(cask_list)
        return [] unless Bundle.cask_installed?
        return [] if cask_list.blank?

        casks.flat_map do |cask|
          next unless cask_list.include?(cask.to_s)

          cask.depends_on[:formula]
        end.compact
      end

      sig { returns(T::Array[Cask::Cask]) }
      private_class_method def self.casks
        return [] unless Bundle.cask_installed?

        require "cask/caskroom"
        @casks ||= T.let(Cask::Caskroom.casks, T.nilable(T::Array[Cask::Cask]))
      end

      sig { params(cask_config: Cask::Config).returns(String) }
      private_class_method def self.explicit_s(cask_config)
        cask_config.explicit.map do |key, value|
          # inverse of #env - converts :languages config key back to --language flag
          if key == :languages
            key = "language"
            value = Array(cask_config.explicit.fetch(:languages, [])).join(",")
          end
          "#{key}: \"#{value.to_s.sub(/^#{Dir.home}/, "~")}\""
        end.join(", ")
      end
    end
  end
end
