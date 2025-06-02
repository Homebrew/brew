# frozen_string_literal: true

require_relative "../command"
require_relative "../local_remote_options"
require_relative "../version_option"
require_relative "../gemcutter_utilities"

class Gem::Commands::YankCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::VersionOption
  include Gem::GemcutterUtilities

  def description # :nodoc:
    <<-EOF
The yank command permanently removes a gem you pushed to a server.

Once you have pushed a gem several downloads will happen automatically
via the webhooks. If you accidentally pushed passwords or other sensitive
data you will need to change them immediately and yank your gem.
    EOF
  end

  def arguments # :nodoc:
    "GEM       name of gem"
  end

  def usage # :nodoc:
    "#{program_name} -v VERSION [-p PLATFORM] [--key KEY_NAME] [--host HOST] GEM"
  end

  def initialize
    super "yank", "Remove a pushed gem from the index"

    add_version_option("remove")
    add_platform_option("remove")
    add_otp_option

    add_option("--host HOST",
               "Yank from another gemcutter-compatible host",
               "  (e.g. https://rubygems.org)") do |value, options|
      options[:host] = value
    end

    add_key_option
    @host = nil
  end

  def execute
    @host = options[:host]

    sign_in @host, scope: get_yank_scope

    version   = get_version_from_requirements(options[:version])
    platform  = get_platform_from_requirements(options)

    if version
      yank_gem(version, platform)
    else
      say "A version argument is required: #{usage}"
      terminate_interaction
    end
  end

  def yank_gem(version, platform)
    say "Yanking gem from #{host}..."
    args = [:delete, version, platform, "api/v1/gems/yank"]
    response = yank_api_request(*args)

    say response.body
  end

  private

  def yank_api_request(method, version, platform, api)
    name = get_one_gem_name
    response = rubygems_api_request(method, api, host, scope: get_yank_scope) do |request|
      request.add_field("Authorization", api_key)

      data = {
        "gem_name" => name,
        "version" => version,
      }
      data["platform"] = platform if platform

      request.set_form_data data
    end
    response
  end

  def get_version_from_requirements(requirements)
    requirements.requirements.first[1].version
  rescue StandardError
    nil
  end

  def get_yank_scope
    :yank_rubygem
  end
end
