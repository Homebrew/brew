# frozen_string_literal: true
##
# The local source finds gems in the current directory for fulfilling
# dependencies.

class Gem::Source::Local < Gem::Source
  def initialize # :nodoc:
    @specs   = nil
    @api_uri = nil
    @uri     = nil
    @load_specs_names = {}
  end

  ##
  # Local sorts before Gem::Source and after Gem::Source::Installed

  def <=>(other)
    case other
    when Gem::Source::Installed,
         Gem::Source::Lock then
      -1
    when Gem::Source::Local then
      0
    when Gem::Source then
      1
    else
      nil
    end
  end

  def inspect # :nodoc:
    keys = @specs ? @specs.keys.sort : "NOT LOADED"
    "#<%s specs: %p>" % [self.class, keys]
  end

  def load_specs(type) # :nodoc:
    @load_specs_names[type] ||= begin
      names = []

      @specs = {}

      Dir["*.gem"].each do |file|
        begin
          pkg = Gem::Package.new(file)
        rescue SystemCallError, Gem::Package::FormatError
          # ignore
        else
          tup = pkg.spec.name_tuple
          @specs[tup] = [File.expand_path(file), pkg]

          case type
          when :released
            unless pkg.spec.version.prerelease?
              names << pkg.spec.name_tuple
            end
          when :prerelease
            if pkg.spec.version.prerelease?
              names << pkg.spec.name_tuple
            end
          when :latest
            tup = pkg.spec.name_tuple

            cur = names.find {|x| x.name == tup.name }
            if !cur
              names << tup
            elsif cur.version < tup.version
              names.delete cur
              names << tup
            end
          else
            names << pkg.spec.name_tuple
          end
        end
      end

      names
    end
  end

  def find_gem(gem_name, version = Gem::Requirement.default, # :nodoc:
               prerelease = false)
    load_specs :complete

    found = []

    @specs.each do |n, data|
      if n.name == gem_name
        s = data[1].spec

        if version.satisfied_by?(s.version)
          if prerelease
            found << s
          elsif !s.version.prerelease? || version.prerelease?
            found << s
          end
        end
      end
    end

    found.max_by {|s| s.version }
  end

  def fetch_spec(name) # :nodoc:
    load_specs :complete

    if data = @specs[name]
      data.last.spec
    else
      raise Gem::Exception, "Unable to find spec for #{name.inspect}"
    end
  end

  def download(spec, cache_dir = nil) # :nodoc:
    load_specs :complete

    @specs.each do |name, data|
      return data[0] if data[1].spec == spec
    end

    raise Gem::Exception, "Unable to find file for '#{spec.full_name}'"
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[Local gems:", "]" do
      q.breakable
      q.seplist @specs.keys do |v|
        q.text v.full_name
      end
    end
  end
end
