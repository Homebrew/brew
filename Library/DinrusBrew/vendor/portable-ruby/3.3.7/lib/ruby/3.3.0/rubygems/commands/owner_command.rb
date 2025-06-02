# frozen_string_literal: true

require_relative "../command"
require_relative "../local_remote_options"
require_relative "../gemcutter_utilities"
require_relative "../text"

class Gem::Commands::OwnerCommand < Gem::Command
  include Gem::Text
  include Gem::LocalRemoteOptions
  include Gem::GemcutterUtilities

  def description # :nodoc:
    <<-EOF
The owner command lets you add and remove owners of a gem on a push
server (the default is https://rubygems.org). Multiple owners can be
added or removed at the same time, if the flag is given multiple times.

The supported user identifiers are dependent on the push server.
For rubygems.org, both e-mail and handle are supported, even though the
user identifier field is called "email".

The owner of a gem has the permission to push new versions, yank existing
versions or edit the HTML page of the gem.  Be careful of who you give push
permission to.
    EOF
  end

  def arguments # :nodoc:
    "GEM       gem to manage owners for"
  end

  def usage # :nodoc:
    "#{program_name} GEM"
  end

  def initialize
    super "owner", "Manage gem owners of a gem on the push server"
    add_proxy_option
    add_key_option
    add_otp_option
    defaults.merge! add: [], remove: []

    add_option "-a", "--add NEW_OWNER", "Add an owner by user identifier" do |value, options|
      options[:add] << value
    end

    add_option "-r", "--remove OLD_OWNER", "Remove an owner by user identifier" do |value, options|
      options[:remove] << value
    end

    add_option "-h", "--host HOST",
               "Use another gemcutter-compatible host",
               "  (e.g. https://rubygems.org)" do |value, options|
      options[:host] = value
    end
  end

  def execute
    @host = options[:host]

    sign_in(scope: get_owner_scope)
    name = get_one_gem_name

    add_owners    name, options[:add]
    remove_owners name, options[:remove]
    show_owners   name
  end

  def show_owners(name)
    Gem.load_yaml

    response = rubygems_api_request :get, "api/v1/gems/#{name}/owners.yaml" do |request|
      request.add_field "Authorization", api_key
    end

    with_response response do |resp|
      owners = Gem::SafeYAML.load clean_text(resp.body)

      say "Owners for gem: #{name}"
      owners.each do |owner|
        say "- #{owner["email"] || owner["handle"] || owner["id"]}"
      end
    end
  end

  def add_owners(name, owners)
    manage_owners :post, name, owners
  end

  def remove_owners(name, owners)
    manage_owners :delete, name, owners
  end

  def manage_owners(method, name, owners)
    owners.each do |owner|
      response = send_owner_request(method, name, owner)
      action = method == :delete ? "Removing" : "Adding"

      with_response response, "#{action} #{owner}"
    rescue Gem::WebauthnVerificationError => e
      raise e
    rescue StandardError
      # ignore early exits to allow for completing the iteration of all owners
    end
  end

  private

  def send_owner_request(method, name, owner)
    rubygems_api_request method, "api/v1/gems/#{name}/owners", scope: get_owner_scope(method: method) do |request|
      request.set_form_data "email" => owner
      request.add_field "Authorization", api_key
    end
  end

  def get_owner_scope(method: nil)
    if method == :post || options.any? && options[:add].any?
      :add_owner
    elsif method == :delete || options.any? && options[:remove].any?
      :remove_owner
    end
  end
end
