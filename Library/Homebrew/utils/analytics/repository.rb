# typed: strict
# frozen_string_literal: true

require "digest"

module Utils
  module Analytics
    # Repository analytics derived from local Git objects.
    class Repository
      # Inherited commits refer to legacy-homebrew PR numbers before these split commits.
      SPLIT_COMMITS = T.let({
        "Homebrew/brew"          => "c5132daf630",
        "Homebrew/homebrew-core" => "c491e31616b4",
      }.freeze, T::Hash[String, String])

      # Legacy issue #2326 (1 September 2010) is the first surviving numbered PR.
      FIRST_LEGACY_PULL_REQUEST = 2326

      # Mailmapped email identities by UTC year, hex-encoded for non-UTF-8 history.
      sig { returns(T::Hash[String, T::Array[String]]) }
      attr_reader :author_identities

      sig { params(path: Pathname, name: String).void }
      def initialize(path, name)
        @path = path
        @name = name
        @author_identities = T.let({}, T::Hash[String, T::Array[String]])
      end

      sig { returns(T::Array[T::Hash[String, T.nilable(T.any(String, Integer))]]) }
      def rows
        raise "Analytics require complete Git history for #{@name}" if git("rev-parse",
                                                                           "--is-shallow-repository") == "true"

        head = git("rev-parse", "HEAD")
        mailmap = git("ls-tree", "HEAD", "--", ".mailmap")
        cask_repository = @name == "Homebrew/homebrew-cask"
        formula_repository = ["Homebrew/homebrew-core", "Homebrew/legacy-homebrew"].include?(@name)
        release_repository = ["Homebrew/brew", "Homebrew/legacy-homebrew"].include?(@name)
        tags = if release_repository
          git("for-each-ref", "--merged=HEAD",
              "--format=%(refname:strip=2)%09%(*committerdate:unix)%09%(committerdate:unix)", "refs/tags")
        else
          ""
        end
        cache = HOMEBREW_CACHE/"analytics/git/#{@name}.json"
        data = cache.exist? ? JSON.parse(cache.read) : {}
        generator = Digest::SHA256.file(__FILE__).hexdigest
        if data["head"] && data.values_at("mailmap", "generator") == [mailmap, generator]
          begin
            git("merge-base", "--is-ancestor", data.fetch("head"), "HEAD")
          rescue ErrorDuringExecution
            data = {}
          end
        else
          data = {}
        end
        year = Time.now.utc.year
        if data.values_at("head", "year", "tags") == [head, year, tags]
          @author_identities = data.fetch("authors")
          return data.fetch("rows")
        end

        authors = data.fetch("authors", {})
        range = data["head"] ? "#{data.fetch("head")}..HEAD" : "HEAD"
        git("log", "--no-merges", "--format=%ct%x09%aE", range).each_line do |line|
          timestamp, email = line.chomp.split("\t", 2)
          next if timestamp.nil? || email.nil?

          commit_year = timestamp_year(timestamp)
          # Historical author addresses can contain non-UTF-8 bytes.
          (authors[commit_year] ||= []) << email.unpack1("H*")
        end
        authors.transform_values!(&:uniq)
        @author_identities = authors
        first_years = authors.keys.sort.each_with_object({}) do |period, first|
          authors.fetch(period).each { |identity| first[identity] ||= period }
        end.values.tally

        pull_requests = data.fetch("pull_requests", {})
        excluded = []
        if (split = SPLIT_COMMITS[@name]) &&
           system("git", "-C", @path.to_s, "cat-file", "-e", "#{split}^{commit}", out: File::NULL, err: File::NULL)
          excluded << "^#{split}^"
        end
        git("log", "--first-parent", "--reverse", "--format=%ct%x00%B%x00", range, *excluded)
          .split("\0").each_slice(2) do |timestamp, message|
            next if message.nil?

            pull_request_numbers(message).each do |number|
              pull_requests[number] ||= timestamp_year(timestamp)
            end
          end
        merged_years = pull_requests.values.tally

        changes = data.fetch("changes", {})
        if cask_repository
          period = ""
          tokens = git("log", "--first-parent", "--reverse", "--raw", "--root", "--no-abbrev",
                       "--diff-merges=first-parent", "--find-renames=100%", "--format=%x00year%x00%ct",
                       "-z", range).split("\0")
          while (token = tokens.shift)
            if token == "year"
              period = timestamp_year(tokens.shift)
              next
            end
            next unless token.lstrip.start_with?(":")

            old_mode, new_mode, _, _, status = token.delete_prefix("\n").delete_prefix(":").split
            old_path = tokens.shift.to_s
            new_path = status&.start_with?("R") ? tokens.shift.to_s : old_path
            before = cask_entry?(old_mode, old_path)
            after = cask_entry?(new_mode, new_path)
            next if before == after

            metric = after ? "added" : "removed"
            period_changes = (changes[period] ||= {})
            period_changes[metric] = period_changes.fetch(metric, 0) + 1
          end
        end

        revisions = data.fetch("year_end_revisions", {})
        missing_years = (2009...year).reject { |y| revisions.key?(y.to_s) }
        if missing_years.any?
          timeline = git("log", "--first-parent", "--format=%ct%x09%H", "HEAD").lines.map do |line|
            timestamp, revision = line.chomp.split("\t", 2)
            [timestamp.to_i, revision]
          end
          missing_years.each do |y|
            revisions[y.to_s] = timeline.find { |timestamp, _| timestamp < Time.utc(y + 1).to_i }&.last
          end
        end

        release_years = tags.lines.filter_map do |line|
          tag, annotated_date, commit_date = line.chomp.split("\t", -1)
          next unless tag&.match?(/\Av?\d+(?:\.\d+){1,2}\z/)

          timestamp_year(annotated_date.presence || commit_date)
        end.tally
        catalogues = data.fetch("catalogues", {})
        maintainers = data.fetch("maintainers", {})
        rows = ["current", *(2009..year).map(&:to_s).reverse].map do |period|
          current = period == "current"
          revision = (current || period == year.to_s) ? head : revisions[period]
          catalogue = if @name == "Homebrew/brew" || revision.nil?
            0
          else
            catalogues[revision] ||= catalogue_count(revision, formula_repository:)
          end
          if @name == "Homebrew/brew" && revision && !maintainers.key?(revision)
            readme = git("ls-tree", "--name-only", revision).lines(chomp: true).find do |file|
              file.match?(/\AREADME(?:\.md)?\z/)
            end
            identities = if readme
              git("show", "#{revision}:#{readme}").split(/\n\s*\n/).select do |paragraph|
                paragraph.match?(/\b(?:maintainers?|Project Leader|Technical Steering Committee)\b/i) &&
                  !paragraph.match?(/\bformer\b/i)
              end.join("\n").scan(%r{\]\(https?://github\.com/([\w-]+)/?\)}).flatten.map(&:downcase).uniq
            end
            maintainers[revision] = identities&.presence&.size
          end
          contributors = (current ? authors.values.flatten : authors.fetch(period, [])).uniq.size
          {
            "period"               => period,
            "revision"             => revision,
            "contributors"         => contributors,
            "new_contributors"     => current ? contributors : first_years.fetch(period, 0),
            "maintainers"          => maintainers[revision],
            "pull_requests_merged" => current ? pull_requests.size : merged_years.fetch(period, 0),
            "added"                => if cask_repository
                                        change_count(changes, period, "added")
            end,
            "removed"              => if cask_repository
                                        change_count(changes, period, "removed")
            end,
            "formulae"             => formula_repository ? catalogue : nil,
            "casks"                => cask_repository ? catalogue : nil,
            "releases"             => if release_repository
                                        if current
                                          release_years.values.sum
                                        else
                                          release_years.fetch(period, 0)
                                        end
            end,
          }
        end
        cache.dirname.mkpath
        cache.atomic_write(JSON.generate({ head:, year:, mailmap:, tags:, authors:, generator:,
                                           year_end_revisions: revisions, catalogues:, maintainers:, changes:,
                                           pull_requests:, rows: }))
        rows
      end

      # Count package files in a historical tree without following aliases.
      sig { params(revision: String, formula_repository: T::Boolean).returns(Integer) }
      def catalogue_count(revision, formula_repository:)
        git("ls-tree", "-rz", revision).split("\0").count do |entry|
          metadata, path = entry.split("\t", 2)
          next false unless metadata&.match?(/\A100(?:644|755) blob /)

          if formula_repository
            path&.match?(%r{\A(?:Library/)?Formula/(?:[^/]+/)?[^/]+\.rb\z})
          else
            path&.match?(%r{\ACasks?/(?:[^/]+/)*[^/]+\.rb\z})
          end
        end
      end

      # Extract PR identities from merge subjects and closing references in this repository.
      sig { params(message: String).returns(T::Array[String]) }
      def pull_request_numbers(message)
        subject = message.lines.first.to_s.chomp
        numbers = [subject[/\AMerge pull request #(\d+)\b/, 1], subject[/\(#(\d+)\)\z/, 1]].compact
        message.scan(/^Closes (.+?)\.?$/i).flatten.each do |reference|
          number = reference[/\A#(\d+)\z/, 1] ||
                   reference[/\A#{Regexp.escape(@name)}#(\d+)\z/i, 1] ||
                   reference[%r{\Ahttps://github\.com/#{Regexp.escape(@name)}/pull/(\d+)\z}i, 1]
          numbers << number if number
        end
        if @name == "Homebrew/legacy-homebrew"
          numbers.reject! { |number| number.to_i < FIRST_LEGACY_PULL_REQUEST }
        end
        numbers.uniq
      end

      sig { params(mode: T.nilable(String), path: String).returns(T::Boolean) }
      def cask_entry?(mode, path)
        %w[100644 100755].include?(mode) && path.match?(%r{\ACasks?/(?:[^/]+/)*[^/]+\.rb\z})
      end
      private :cask_entry?

      sig { params(timestamp: T.nilable(String)).returns(String) }
      def timestamp_year(timestamp)
        Time.at(timestamp.to_i).utc.year.to_s
      end
      private :timestamp_year

      sig { params(changes: T::Hash[String, T::Hash[String, Integer]], period: String, metric: String).returns(Integer) }
      def change_count(changes, period, metric)
        if period == "current"
          changes.values.sum { |counts| counts.fetch(metric, 0) }
        else
          changes.fetch(period, {}).fetch(metric, 0)
        end
      end
      private :change_count

      sig { params(args: String).returns(String) }
      def git(*args)
        Utils.safe_popen_read("git", "-C", @path.to_s, *args).strip
      end
    end
  end
end
