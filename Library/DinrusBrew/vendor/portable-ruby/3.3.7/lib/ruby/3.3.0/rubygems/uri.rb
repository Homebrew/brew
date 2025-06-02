# frozen_string_literal: true

##
# The Uri handles rubygems source URIs.
#

class Gem::Uri
  ##
  # Parses and redacts uri

  def self.redact(uri)
    new(uri).redacted
  end

  ##
  # Parses uri, raising if it's invalid

  def self.parse!(uri)
    require_relative "vendor/uri/lib/uri"

    raise Gem::URI::InvalidURIError unless uri

    return uri unless uri.is_a?(String)

    # Always escape URI's to deal with potential spaces and such
    # It should also be considered that source_uri may already be
    # a valid URI with escaped characters. e.g. "{DESede}" is encoded
    # as "%7BDESede%7D". If this is escaped again the percentage
    # symbols will be escaped.
    begin
      Gem::URI.parse(uri)
    rescue Gem::URI::InvalidURIError
      Gem::URI.parse(Gem::URI::DEFAULT_PARSER.escape(uri))
    end
  end

  ##
  # Parses uri, returning the original uri if it's invalid

  def self.parse(uri)
    parse!(uri)
  rescue Gem::URI::InvalidURIError
    uri
  end

  def initialize(source_uri)
    @parsed_uri = parse(source_uri)
  end

  def redacted
    return self unless valid_uri?

    if token? || oauth_basic?
      with_redacted_user
    elsif password?
      with_redacted_password
    else
      self
    end
  end

  def to_s
    @parsed_uri.to_s
  end

  def redact_credentials_from(text)
    return text unless valid_uri? && password? && text.include?(to_s)

    text.sub(password, "REDACTED")
  end

  def method_missing(method_name, *args, &blk)
    if @parsed_uri.respond_to?(method_name)
      @parsed_uri.send(method_name, *args, &blk)
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    @parsed_uri.respond_to?(method_name, include_private) || super
  end

  protected

  # Add a protected reader for the cloned instance to access the original object's parsed uri
  attr_reader :parsed_uri

  private

  def parse!(uri)
    self.class.parse!(uri)
  end

  def parse(uri)
    self.class.parse(uri)
  end

  def with_redacted_user
    clone.tap {|uri| uri.user = "REDACTED" }
  end

  def with_redacted_password
    clone.tap {|uri| uri.password = "REDACTED" }
  end

  def valid_uri?
    !@parsed_uri.is_a?(String)
  end

  def password?
    !!password
  end

  def oauth_basic?
    password == "x-oauth-basic"
  end

  def token?
    !user.nil? && password.nil?
  end

  def initialize_copy(original)
    @parsed_uri = original.parsed_uri.clone
  end
end
