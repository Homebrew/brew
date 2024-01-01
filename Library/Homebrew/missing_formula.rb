# typed: true
# frozen_string_literal: true

require "formulary"

module Homebrew
  # Helper module for checking if there is a reason a formula is missing.
  #
  # @api private
  module MissingFormula
    class << self
      def reason(name, silent: false, show_info: false)
        cask_reason(name, silent: silent, show_info: show_info) || disallowed_reason(name) ||
          tap_migration_reason(name) || deleted_reason(name, silent: silent)
      end

      def disallowed_reason(name)
        case name.downcase
        when "gem", /^rubygems?$/ then <<~EOS
          macOS provides gem as part of Ruby. To install a newer version:
            brew install ruby
        EOS
        when "pip" then <<~EOS
          pip is part of the python formula:
            brew install python
        EOS
        when "pil" then <<~EOS
          Instead of PIL, consider pillow:
            brew install pillow
        EOS
        when "macruby" then <<~EOS
          MacRuby has been discontinued. Consider RubyMotion:
            brew install --cask rubymotion
        EOS
        when /(lib)?lzma/ then <<~EOS
          lzma is now part of the xz formula:
            brew install xz
        EOS
        when "gsutil" then <<~EOS
          gsutil is available through pip:
            pip3 install gsutil
        EOS
        when "gfortran" then <<~EOS
          GNU Fortran is part of the GCC formula:
            brew install gcc
        EOS
        when "play" then <<~EOS
          Play 2.3 replaces the play command with activator:
            brew install typesafe-activator

          You can read more about this change at:
            #{Formatter.url("https://www.playframework.com/documentation/2.3.x/Migration23")}
            #{Formatter.url("https://www.playframework.com/documentation/2.3.x/Highlights23")}
        EOS
        when "haskell-platform" then <<~EOS
          The components of the Haskell Platform are available separately.

          Glasgow Haskell Compiler:
            brew install ghc

          Cabal build system:
            brew install cabal-install

          Haskell Stack tool:
            brew install haskell-stack
        EOS
        when "mysqldump-secure" then <<~EOS
          The creator of mysqldump-secure tried to game our popularity metrics.
        EOS
        when "ngrok" then <<~EOS
          Upstream sunsetted 1.x in March 2016 and 2.x is not open-source.

          If you wish to use the 2.x release you can install it with:
            brew install --cask ngrok
        EOS
        when "cargo" then <<~EOS
          cargo is part of the rust formula:
            brew install rust
        EOS
        when "cargo-completion" then <<~EOS
          cargo-completion is part of the rust formula:
            brew install rust
        EOS
        when "uconv" then <<~EOS
          uconv is part of the icu4c formula:
            brew install icu4c
        EOS
        when "postgresql", "postgres" then <<~EOS
          postgresql breaks existing databases on upgrade without human intervention.

          See a more specific version to install with:
            brew formulae | grep postgresql@
        EOS
        end
      end
      alias generic_disallowed_reason disallowed_reason

      def tap_migration_reason(name)
        message = T.let(nil, T.nilable(String))

        Tap.each do |old_tap|
          new_tap = old_tap.tap_migrations[name]
          next unless new_tap

          new_tap_user, new_tap_repo, new_tap_new_name = new_tap.split("/")
          new_tap_name = "#{new_tap_user}/#{new_tap_repo}"

          message = <<~EOS
            It was migrated from #{old_tap} to #{new_tap}.
          EOS
          break if new_tap_name == CoreTap.instance.name

          install_cmd = if new_tap_name.start_with?("homebrew/cask")
            "install --cask"
          else
            "install"
          end
          new_tap_new_name ||= name

          message += <<~EOS
            You can access it again by running:
              brew tap #{new_tap_name}
            And then you can install it by running:
              brew #{install_cmd} #{new_tap_new_name}
          EOS
          break
        end

        message
      end

      def deleted_reason(name, silent: false)
        path = Formulary.path name
        return if File.exist? path

        tap = Tap.from_path(path)
        return if tap.nil? || !File.exist?(tap.path)

        relative_path = path.relative_path_from tap.path

        tap.path.cd do
          unless silent
            ohai "Searching for a previously deleted formula (in the last month)..."
            if (tap.path/".git/shallow").exist?
              opoo <<~EOS
                #{tap} is shallow clone. To get its complete history, run:
                  git -C "$(brew --repo #{tap})" fetch --unshallow

              EOS
            end
          end

          # Optimization for the core tap which has many monthly commits
          if tap.core_tap?
            # Check if the formula has been deleted in the last month.
            diff_command = ["git", "diff", "--diff-filter=D", "--name-only",
                            "@{'1 month ago'}", "--", relative_path]
            deleted_formula = Utils.popen_read(*diff_command)

            if deleted_formula.blank?
              ofail "No previously deleted formula found." unless silent
              return
            end
          end

          # Find commit where formula was deleted in the last month.
          log_command = "git log --since='1 month ago' --diff-filter=D " \
                        "--name-only --max-count=1 " \
                        "--format=%H\\\\n%h\\\\n%B -- #{relative_path}"
          hash, short_hash, *commit_message, relative_path =
            Utils.popen_read(log_command).gsub("\\n", "\n").lines.map(&:chomp)

          if hash.blank? || short_hash.blank? || relative_path.blank?
            ofail "No previously deleted formula found." unless silent
            return
          end

          commit_message = commit_message.reject(&:empty?).join("\n  ")

          commit_message.sub!(/ \(#(\d+)\)$/, " (#{tap.issues_url}/\\1)")
          commit_message.gsub!(/(Closes|Fixes) #(\d+)/, "\\1 #{tap.issues_url}/\\2")

          <<~EOS
            #{name} was deleted from #{tap.name} in commit #{short_hash}:
              #{commit_message}

            To show the formula before removal, run:
              git -C "$(brew --repo #{tap})" show #{short_hash}^:#{relative_path}

            If you still use this formula, consider creating your own tap:
              #{Formatter.url("https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap")}
          EOS
        end
      end

      def cask_reason(name, silent: false, show_info: false); end

      def suggest_command(name, command); end

      require "extend/os/missing_formula"
    end
  end
end
