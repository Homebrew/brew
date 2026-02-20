# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module UvInstaller
      sig { void }
      def self.reset!
        @installed_packages = nil
      end

      sig {
        params(
          name:      String,
          verbose:   T::Boolean,
          specifier: T.nilable(String),
          with:      T::Array[String],
          _options:  T.anything,
        ).returns(T::Boolean)
      }
      def self.preinstall!(name, verbose: false, specifier: nil, with: [], **_options)
        unless Bundle.uv_installed?
          puts "Installing uv. It is not currently installed." if verbose
          Bundle.brew("install", "--formula", "uv", verbose:)
          Bundle.reset!
          raise "Unable to install #{name} uv tool. uv installation failed." unless Bundle.uv_installed?
        end

        if package_installed?(name, specifier:, with:)
          puts "Skipping install of #{name} uv tool. It is already installed." if verbose
          return false
        end

        true
      end

      sig {
        params(
          name:       String,
          preinstall: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          specifier:  T.nilable(String),
          with:       T::Array[String],
          _options:   T.anything,
        ).returns(T::Boolean)
      }
      def self.install!(name, preinstall: true, verbose: false, force: false, specifier: nil, with: [], **_options)
        return true unless preinstall

        puts "Installing #{name} uv tool. It is not currently installed." if verbose

        uv = T.must(Bundle.which_uv)
        args = ["tool", "install", requirement(name, specifier)]
        normalized_with = normalize_with(with)
        normalized_with.each do |requirement|
          args << "--with"
          args << requirement
        end

        success = Bundle.system uv.to_s, *args, verbose: verbose
        return false unless success

        installed_packages << normalized_options(name, specifier:, with:)
        true
      end

      sig {
        params(
          package:   String,
          specifier: T.nilable(String),
          with:      T::Array[String],
        ).returns(T::Boolean)
      }
      def self.package_installed?(package, specifier: nil, with: [])
        desired = normalized_options(package, specifier:, with:)
        installed_packages.any? do |installed|
          installed_name = T.cast(installed[:name], String)
          installed_with = T.cast(installed[:with] || [], T::Array[String])
          installed_name == desired[:name] &&
            installed[:specifier] == desired[:specifier] &&
            installed_with == desired[:with]
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def self.installed_packages
        require "bundle/uv_dumper"
        @installed_packages ||= T.let(Homebrew::Bundle::UvDumper.packages,
                                      T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
      end

      sig { params(name: String, specifier: T.nilable(String)).returns(String) }
      def self.requirement(name, specifier)
        "#{name}#{specifier}"
      end

      sig { params(with: T::Array[String]).returns(T::Array[String]) }
      def self.normalize_with(with)
        with.map(&:strip)
            .reject(&:empty?)
            .uniq
            .sort
      end

      sig { params(name: String).returns(String) }
      def self.normalize_name(name)
        match = name.strip.match(/\A(?<base>[^\[\]]+)(?:\[(?<extras>[^\]]+)\])?\z/)
        return name.strip unless match

        base = T.must(match[:base]).strip
        extras_raw = match[:extras]
        return base if extras_raw.blank?

        extras = extras_raw.split(",").map(&:strip).reject(&:empty?).uniq.sort
        return base if extras.empty?

        "#{base}[#{extras.join(",")}]"
      end

      sig {
        params(
          name:      String,
          specifier: T.nilable(String),
          with:      T::Array[String],
        ).returns(T::Hash[Symbol, T.untyped])
      }
      def self.normalized_options(name, specifier:, with:)
        {
          name:      normalize_name(name),
          specifier: specifier.presence,
          with:      normalize_with(with),
        }
      end
    end
  end
end
