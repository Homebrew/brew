# frozen_string_literal: true

##
# An InstalledSpecification represents a gem that is already installed
# locally.

class Gem::Resolver::InstalledSpecification < Gem::Resolver::SpecSpecification
  def ==(other) # :nodoc:
    self.class === other &&
      @set  == other.set &&
      @spec == other.spec
  end

  ##
  # This is a null install as this specification is already installed.
  # +options+ are ignored.

  def install(options = {})
    yield nil
  end

  ##
  # Returns +true+ if this gem is installable for the current platform.

  def installable_platform?
    # BACKCOMPAT If the file is coming out of a specified file, then we
    # ignore the platform. This code can be removed in RG 3.0.
    return true if @source.is_a? Gem::Source::SpecificFile

    super
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[InstalledSpecification", "]" do
      q.breakable
      q.text "name: #{name}"

      q.breakable
      q.text "version: #{version}"

      q.breakable
      q.text "platform: #{platform}"

      q.breakable
      q.text "dependencies:"
      q.breakable
      q.pp spec.dependencies
    end
  end

  ##
  # The source for this specification

  def source
    @source ||= Gem::Source::Installed.new
  end
end
