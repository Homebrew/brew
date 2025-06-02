# frozen_string_literal: true

##
# A LocalSpecification comes from a .gem file on the local filesystem.

class Gem::Resolver::LocalSpecification < Gem::Resolver::SpecSpecification
  ##
  # Returns +true+ if this gem is installable for the current platform.

  def installable_platform?
    return true if @source.is_a? Gem::Source::SpecificFile

    super
  end

  def local? # :nodoc:
    true
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[LocalSpecification", "]" do
      q.breakable
      q.text "name: #{name}"

      q.breakable
      q.text "version: #{version}"

      q.breakable
      q.text "platform: #{platform}"

      q.breakable
      q.text "dependencies:"
      q.breakable
      q.pp dependencies

      q.breakable
      q.text "source: #{@source.path}"
    end
  end
end
