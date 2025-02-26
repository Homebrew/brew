# typed: true
# frozen_string_literal: true

module Service
  module Commands
    module Info
      TRIGGERS = %w[info i].freeze

      def self.run(targets, verbose:, json:)
        return unless ServicesCli.check(targets)

        output = targets.map(&:to_hash)

        if json
          puts JSON.pretty_generate(output)
          return
        end

        output.each do |hash|
          puts output(hash, verbose:)
        end
      end

      def self.pretty_bool(bool)
        return bool if !$stdout.tty? || Homebrew::EnvConfig.no_emoji?

        if bool
          "#{Tty.bold}#{Formatter.success("✔")}#{Tty.reset}"
        else
          "#{Tty.bold}#{Formatter.error("✘")}#{Tty.reset}"
        end
      end

      def self.output(hash, verbose:)
        out = "#{Tty.bold}#{hash[:name]}#{Tty.reset} (#{hash[:service_name]})\n"
        out += "Running: #{pretty_bool(hash[:running])}\n"
        out += "Loaded: #{pretty_bool(hash[:loaded])}\n"
        out += "Schedulable: #{pretty_bool(hash[:schedulable])}\n"
        out += "User: #{hash[:user]}\n" unless hash[:pid].nil?
        out += "PID: #{hash[:pid]}\n" unless hash[:pid].nil?
        return out unless verbose

        out += "File: #{hash[:file]} #{pretty_bool(hash[:file].present?)}\n"
        out += "Command: #{hash[:command]}\n" unless hash[:command].nil?
        out += "Working directory: #{hash[:working_dir]}\n" unless hash[:working_dir].nil?
        out += "Root directory: #{hash[:root_dir]}\n" unless hash[:root_dir].nil?
        out += "Log: #{hash[:log_path]}\n" unless hash[:log_path].nil?
        out += "Error log: #{hash[:error_log_path]}\n" unless hash[:error_log_path].nil?
        out += "Interval: #{hash[:interval]}s\n" unless hash[:interval].nil?
        out += "Cron: #{hash[:cron]}\n" unless hash[:cron].nil?

        out
      end
    end
  end
end
