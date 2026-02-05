# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "install"
require "system_config"
require "stringio"
require "socket"

module Homebrew
  module Cmd
    class GistLogs < AbstractCommand
      include Install

      cmd_args do
        description <<~EOS
          Upload logs for a failed build of <formula> to a new Gist. Presents an
          error message if no logs are found.
        EOS
        switch "--with-hostname",
               description: "Include the hostname in the Gist."
        switch "-n", "--new-issue",
               description: "Automatically create a new issue in the appropriate GitHub repository " \
                            "after creating the Gist."
        switch "-p", "--private",
               description: "The Gist will be marked private and will not appear in listings but will " \
                            "be accessible with its link."

        named_args :formula, number: 1
      end

      sig { override.void }
      def run
        Install.perform_preinstall_checks_once(all_fatal: true)
        Install.perform_build_from_source_checks(all_fatal: true)
        return unless (formula = args.named.to_resolved_formulae.first)

        gistify_logs(formula)
      end

      # Truncates a text string to fit within a byte size constraint,
      # preserving character encoding validity. The returned string will
      # be not much longer than the specified max_bytes, though the exact
      # shortfall or overrun may vary.
      sig { params(str: String, max_bytes: Integer, options: T::Hash[Symbol, T.untyped]).returns(String) }
      def self.truncate_text_to_approximate_size(str, max_bytes, options = {})
        front_weight = options.fetch(:front_weight, 0.5)
        raise "opts[:front_weight] must be between 0.0 and 1.0" if front_weight < 0.0 || front_weight > 1.0
        return str if str.bytesize <= max_bytes

        glue = "\n[...snip...]\n"
        max_bytes_in = [max_bytes - glue.bytesize, 1].max
        bytes = str.dup.force_encoding("BINARY")
        glue_bytes = glue.encode("BINARY")
        n_front_bytes = (max_bytes_in * front_weight).floor
        n_back_bytes = max_bytes_in - n_front_bytes
        if n_front_bytes.zero?
          front = bytes[1..0]
          back = bytes[-max_bytes_in..]
        elsif n_back_bytes.zero?
          front = bytes[0..(max_bytes_in - 1)]
          back = bytes[1..0]
        else
          front = bytes[0..(n_front_bytes - 1)]
          back = bytes[-n_back_bytes..]
        end
        out = T.must(front) + glue_bytes + T.must(back)
        out.force_encoding("UTF-8")
        out.encode!("UTF-16", invalid: :replace)
        out.encode!("UTF-8")
        out
      end

      private

      sig { params(formula: Formula).void }
      def gistify_logs(formula)
        files = load_logs(formula.logs)
        build_time = formula.logs.ctime
        timestamp = build_time.strftime("%Y-%m-%d_%H-%M-%S")

        s = StringIO.new
        SystemConfig.dump_verbose_config s
        # Dummy summary file, asciibetically first, to control display title of gist
        files["# #{formula.name} - #{timestamp}.txt"] = {
          content: brief_build_info(formula, with_hostname: args.with_hostname?),
        }
        files["00.config.out"] = { content: s.string }
        files["00.doctor.out"] = { content: Utils.popen_read("#{HOMEBREW_PREFIX}/bin/brew", "doctor", err: :out) }
        unless formula.core_formula?
          tap = <<~EOS
            Formula: #{formula.name}
                Tap: #{formula.tap}
               Path: #{formula.path}
          EOS
          files["00.tap.out"] = { content: tap }
        end

        if GitHub::API.credentials_type == :none
          odie "`brew gist-logs` requires `$HOMEBREW_GITHUB_API_TOKEN` to be set!"
        end

        # Description formatted to work well as page title when viewing gist
        descr = if formula.core_formula?
          "#{formula.name} on #{OS_VERSION} - Homebrew build logs"
        else
          "#{formula.name} (#{formula.full_name}) on #{OS_VERSION} - Homebrew build logs"
        end

        begin
          url = GitHub.create_gist(files, descr, private: args.private?)
        rescue GitHub::API::HTTPNotFoundError
          odie <<~EOS
            Your GitHub API token likely doesn't have the `gist` scope.
            #{GitHub.pat_blurb(GitHub::CREATE_GIST_SCOPES)}
          EOS
        end

        if args.new_issue?
          url = GitHub.create_issue(formula.tap, "#{formula.name} failed to build on #{OS_VERSION}",
                                    url)
        end

        puts url if url
      end

      sig { params(formula: Formula, with_hostname: T::Boolean).returns(String) }
      def brief_build_info(formula, with_hostname:)
        build_time_string = formula.logs.ctime.strftime("%Y-%m-%d %H:%M:%S")
        string = <<~EOS
          Homebrew build logs for #{formula.full_name} on #{OS_VERSION}
        EOS
        if with_hostname
          hostname = Socket.gethostname
          string << "Host: #{hostname}\n"
        end
        string << "Build date: #{build_time_string}\n"
        string.freeze
      end

      # Causes some terminals to display secure password entry indicators.
      sig { void }
      def noecho_gets
        system "stty", "-echo"
        result = $stdin.gets
        system "stty", "echo"
        puts
        result
      end

      sig { params(dir: Pathname, basedir: Pathname).returns(T::Hash[String, T::Hash[Symbol, String]]) }
      def load_logs(dir, basedir = dir)
        logs = {}
        if dir.exist?
          dir.children.sort.each do |file|
            if file.directory?
              logs.merge! load_logs(file, basedir)
            else
              contents = file.size? ? file.read : "empty log"
              # small enough to avoid GitHub "unicorn" page-load-timeout errors
              max_file_size = 1_000_000
              contents = GistLogs.truncate_text_to_approximate_size(contents, max_file_size, front_weight: 0.2)
              logs[file.relative_path_from(basedir).to_s.tr("/", ":")] = { content: contents }
            end
          end
        end
        odie "No logs." if logs.empty?

        logs
      end
    end
  end
end
