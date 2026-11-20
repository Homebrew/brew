# typed: strict
# frozen_string_literal: true

require "digest"

module Utils
  module Analytics
    # Release analytics derived from stable Git tags and their commit ranges.
    class Releases
      sig { params(path: Pathname).void }
      def initialize(path)
        @path = path
      end

      sig { returns(T::Hash[String, T.anything]) }
      def report
        if git("rev-parse", "--is-shallow-repository") == "true"
          raise "Release analytics require complete brew Git history"
        end

        tags = git("for-each-ref", "--merged=HEAD",
                   "--format=%(refname:strip=2)%09%(objectname)%09%(*objectname)%09" \
                   "%(committerdate:unix)%09%(*committerdate:unix)", "refs/tags").lines.filter_map do |line|
          name, revision, annotated_revision, timestamp, annotated_timestamp = line.chomp.split("\t", -1)
          next if name.nil? || revision.nil? || timestamp.nil?
          next unless name.match?(/\Av?\d+(?:\.\d+){1,2}\z/)

          [name, annotated_revision.presence || revision, annotated_timestamp.presence || timestamp]
        end
        signature = Digest::SHA256.hexdigest([
          Digest::SHA256.file(__FILE__).hexdigest, git("ls-tree", "HEAD", "--", ".mailmap")
        ].join("\n"))
        cache = HOMEBREW_CACHE/"analytics/git/releases.json"
        data = cache.exist? ? JSON.parse(cache.read) : {}
        data = {} if data["signature"] != signature
        if data["tags"] != tags
          first_parents = git("rev-list", "--parents", "HEAD").lines.to_h do |line|
            revision, parent = line.split
            [revision, parent || ""]
          end
          versions = tags.to_h { |name, revision, _| [revision, name] }
          saved = data.fetch("releases", []).to_h { |row| [row.fetch("version"), row] }
          releases = tags.map do |name, revision, timestamp|
            previous = first_parents.fetch(revision, "")
            previous = first_parents.fetch(previous, "") until previous.empty? || versions.key?(previous)
            row = saved[name]
            next row if row && row["revision"] == revision && row["previous_revision"] == previous.presence

            {
              "version"           => name,
              "revision"          => revision,
              "previous_version"  => versions[previous],
              "previous_revision" => previous.presence,
              "date"              => Time.at(timestamp.to_i).utc.strftime("%F"),
            }.merge(statistics(previous.empty? ? revision : "#{previous}..#{revision}"))
          end
          data["releases"] = releases.sort_by do |row|
            [row.fetch("date"), Version.new(row.fetch("version"))]
          end.reverse
          seen = Set.new
          data.fetch("releases").reverse_each do |row|
            identities = row.fetch("authors")
            row["new_contributors"] = (identities - seen.to_a).size
            seen.merge(identities)
          end
          boundaries = data.fetch("releases").select { |row| row.fetch("version").end_with?(".0") }
          boundaries.sort_by! { |row| Version.new(row.fetch("version")) }
          boundaries.reverse!
          data["aggregates"] = boundaries.filter_map do |row|
            version = Version.new(row.fetch("version"))
            kind = version.minor.to_i.zero? ? "major" : "minor"
            previous = boundaries.find do |candidate|
              value = Version.new(candidate.fetch("version"))
              value < version && (kind == "minor" || value.minor.to_i.zero?)
            end
            next unless previous

            saved = data.fetch("aggregates", []).find do |candidate|
              candidate["revision"] == row["revision"] && candidate["previous_revision"] == previous["revision"]
            end
            next saved if saved

            aggregate = row.slice("version", "revision", "date").merge(
              "kind" => kind, "previous_version" => previous.fetch("version"),
              "previous_revision" => previous.fetch("revision")
            ).merge(statistics("#{previous.fetch("revision")}..#{row.fetch("revision")}"))
            earlier = git("log", "--no-merges", "--format=%aE", previous.fetch("revision"))
                      .b
                      .lines(chomp: true)
                      .map { |email| email.unpack1("H*") }
            aggregate["new_contributors"] = (aggregate.fetch("authors") - earlier).size
            aggregate
          end
          data["totals"] = statistics(*tags.map { |_, revision, _| revision }).except("authors")
          data["totals"]["releases"] = tags.size
          data["totals"]["new_contributors"] = data.fetch("totals").fetch("contributors")
          data["tags"] = tags
          data["signature"] = signature
          cache.dirname.mkpath
          cache.atomic_write(JSON.generate(data))
        end
        releases = data.fetch("releases").map { |row| row.except("authors") }
        years = releases.map { |row| row.fetch("date")[0, 4] }.tally
        {
          "generated_at" => Time.now.utc.iso8601,
          "source"       => "https://github.com/Homebrew/brew",
          "revision"     => git("rev-parse", "HEAD"),
          "years"        => [{ "period" => "current", "releases" => releases.size },
                             *(2009..Time.now.utc.year).to_a.reverse.map do |year|
                               { "period" => year.to_s, "releases" => years.fetch(year.to_s, 0) }
                             end],
          "releases"     => releases,
          "aggregates"   => data.fetch("aggregates").map { |row| row.except("authors") },
          "totals"       => data.fetch("totals"),

        }
      end

      sig { params(revisions: String).returns(T::Hash[String, T.anything]) }
      def statistics(*revisions)
        authors = Set.new
        pull_requests = Set.new
        commits = 0
        unless revisions.empty?
          git("log", "--format=%P%x09%aE%x09%s", *revisions).b.each_line do |line|
            parents, email, subject = line.chomp.split("\t", 3)
            next if parents.nil? || email.nil? || subject.nil?

            if parents.split.size < 2
              commits += 1
              authors << email
            end
            number = subject[/\AMerge pull request #(\d+)\b/, 1] || subject[/\(#(\d+)\)\z/, 1]
            pull_requests << number if number
          end
        end
        { "commits" => commits, "pull_requests" => pull_requests.size, "contributors" => authors.size,
          "authors" => authors.map { |email| email.unpack1("H*") } }
      end

      sig { params(args: String).returns(String) }
      def git(*args)
        Utils.safe_popen_read("git", "-C", @path.to_s, args:).chomp
      end
    end
  end
end
