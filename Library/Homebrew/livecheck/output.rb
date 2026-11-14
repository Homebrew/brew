# typed: strict
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # Human-readable and structured livecheck results.
    module Output
      extend T::Helpers

      requires_ancestor { T.class_of(Livecheck) }

      sig {
        params(
          package_or_resource: T.any(Formula, Cask::Cask, Resource),
          status_str:          String,
          messages:            T.nilable(T::Array[String]),
          full_name:           T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Hash[Symbol, T.untyped])
      }
      def status_hash(package_or_resource, status_str, messages = nil, full_name: false, verbose: false)
        formula = package_or_resource if package_or_resource.is_a?(Formula)
        cask = package_or_resource if package_or_resource.is_a?(Cask::Cask)
        resource = package_or_resource if package_or_resource.is_a?(Resource)

        status_hash = {}
        if formula
          status_hash[:formula] = formula_name(formula, full_name:)
        elsif cask
          status_hash[:cask] = cask_name(cask, full_name:)
        elsif resource
          status_hash[:resource] = resource.name
        end
        status_hash[:status] = status_str
        status_hash[:messages] = messages if messages.is_a?(Array)

        status_hash[:meta] = {
          livecheck_defined: package_or_resource.livecheck_defined?,
        }
        status_hash[:meta][:head_only] = true if formula&.head_only?

        status_hash
      end

      sig {
        params(url: String, regex: T.nilable(Regexp), strategy_url: T.nilable(String), final_url: T.nilable(String),
               strategy_regex: T.nilable(Regexp), cached: T.nilable(T::Boolean)).void
      }
      def print_strategy_result(url:, regex:, strategy_url:, final_url:, strategy_regex:, cached:)
        puts "URL (strategy):   #{strategy_url}" if strategy_url.present? && strategy_url != url
        puts "URL (final):      #{final_url}" if final_url.present?
        puts "Regex (strategy): #{strategy_regex.inspect}" if strategy_regex.present? && strategy_regex != regex
        puts "Cached?:          Yes" if cached == true
      end
      private :print_strategy_result

      sig {
        params(original_url: String, url: String, url_spec: T.nilable(T.any(String, Symbol)),
               url_options: T::Hash[Symbol, T.anything], strategies: T::Array[T::Class[Strategic]],
               strategy: T.nilable(T::Class[Strategic]), regex: T.nilable(Regexp), verbose: T::Boolean).void
      }
      def print_strategy_info(original_url:, url:, url_spec:, url_options:, strategies:, strategy:, regex:,
                              verbose:)
        puts
        if url_spec.is_a?(Symbol)
          # This assumes the URL symbol will fit within the available space.
          puts "URL (#{url_spec}):".ljust(18, " ") + original_url
        elsif original_url.present? && original_url != "None"
          puts "URL:              #{original_url}"
        end
        puts "URL (processed):  #{url}" if url != original_url
        puts "URL Options:      #{url_options}" if url_options.present?
        if strategies.present? && verbose
          puts "Strategies:       #{strategies.map { |s| livecheck_strategy_names(s) }.join(", ")}"
        end
        puts "Strategy:         #{livecheck_strategy_names(strategy)}" if strategy
        puts "Regex:            #{regex.inspect}" if regex.present?
      end
      private :print_strategy_info

      sig { params(matches: T::Hash[String, Version], verbose: T::Boolean, heading: String).void }
      def print_matches(matches, verbose:, heading: "Matched Versions")
        puts
        puts "#{heading}:"
        if verbose
          matches.each do |match, version|
            puts Tty.strip_ansi("#{match} => #{version.inspect}")
          end
        elsif matches.present?
          puts Tty.strip_ansi(matches.values.join(", "))
        end
      end
      private :print_matches

      private

      # Formats and prints the livecheck result for a formula/cask/resource.
      sig { params(info: T::Hash[Symbol, T.untyped], verbose: T::Boolean, ambiguous_cask: T::Boolean).void }
      def print_latest_version(info, verbose: false, ambiguous_cask: false)
        package_or_resource_s = info[:resource].present? ? "  " : ""
        package_or_resource = Tty.strip_ansi((info[:formula] || info[:cask] || info[:resource]).to_s)
        package_or_resource_s += "#{Tty.blue}#{package_or_resource}#{Tty.reset}"
        package_or_resource_s += " (cask)" if ambiguous_cask
        package_or_resource_s += " (guessed)" if verbose && !info[:meta][:livecheck_defined]

        current = Tty.strip_ansi(info[:version][:current].to_s)
        current_s = if info[:version][:newer_than_upstream]
          "#{Tty.red}#{current}#{Tty.reset}"
        else
          current
        end

        latest = Tty.strip_ansi(info[:version][:latest].to_s)
        latest_s = if info[:version][:outdated]
          "#{Tty.green}#{latest}#{Tty.reset}"
        else
          latest
        end

        puts "#{package_or_resource_s}: #{current_s} ==> #{latest_s}"
      end

      # Prints the livecheck result for the resources of a given Formula.
      sig { params(info: T::Array[T::Hash[Symbol, T.untyped]], verbose: T::Boolean).void }
      def print_resources_info(info, verbose: false)
        info.each do |r_info|
          if r_info[:status] && r_info[:messages]
            SkipConditions.print_skip_information(r_info)
          else
            print_latest_version(r_info, verbose:)
          end
        end
      end
    end
  end
end
