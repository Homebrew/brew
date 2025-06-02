# frozen_string_literal: true

module Bundler
  class Settings
    class Validator
      class Rule
        attr_reader :description

        def initialize(keys, description, &validate)
          @keys = keys
          @description = description
          @validate = validate
        end

        def validate!(key, value, settings)
          instance_exec(key, value, settings, &@validate)
        end

        def fail!(key, value, *reasons)
          reasons.unshift @description
          raise InvalidOption, "Setting `#{key}` to #{value.inspect} failed:\n#{reasons.map {|r| " - #{r}" }.join("\n")}"
        end

        def set(settings, key, value, *reasons)
          hash_key = k(key)
          return if settings[hash_key] == value
          reasons.unshift @description
          Bundler.ui.info "Setting `#{key}` to #{value.inspect}, since #{reasons.join(", ")}"
          if value.nil?
            settings.delete(hash_key)
          else
            settings[hash_key] = value
          end
        end

        def k(key)
          Bundler.settings.key_for(key)
        end
      end

      def self.rules
        @rules ||= Hash.new {|h, k| h[k] = [] }
      end
      private_class_method :rules

      def self.rule(keys, description, &blk)
        rule = Rule.new(keys, description, &blk)
        keys.each {|k| rules[k] << rule }
      end
      private_class_method :rule

      def self.validate!(key, value, settings)
        rules_to_validate = rules[key]
        rules_to_validate.each {|rule| rule.validate!(key, value, settings) }
      end

      rule %w[path path.system], "path and path.system are mutually exclusive" do |key, value, settings|
        if key == "path" && value
          set(settings, "path.system", nil)
        elsif key == "path.system" && value
          set(settings, :path, nil)
        end
      end

      rule %w[with without], "a group cannot be in both `with` & `without` simultaneously" do |key, value, settings|
        with = settings.fetch(k(:with), "").split(":").map(&:to_sym)
        without = settings.fetch(k(:without), "").split(":").map(&:to_sym)

        other_key = key == "with" ? :without : :with
        other_setting = key == "with" ? without : with

        conflicting = with & without
        if conflicting.any?
          fail!(key, value, "`#{other_key}` is current set to #{other_setting.inspect}", "the `#{conflicting.join("`, `")}` groups conflict")
        end
      end

      rule %w[path], "relative paths are expanded relative to the current working directory" do |key, value, settings|
        next if value.nil?

        path = Pathname.new(value)
        next if !path.relative? || !Bundler.feature_flag.path_relative_to_cwd?

        path = path.expand_path

        root = begin
                 Bundler.root
               rescue GemfileNotFound
                 Pathname.pwd.expand_path
               end

        path = begin
                 path.relative_path_from(root)
               rescue ArgumentError
                 path
               end

        set(settings, key, path.to_s)
      end
    end
  end
end
