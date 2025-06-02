# frozen_string_literal: true

require "digest/md5"
require "strscan"

# Net::IMAP authenticator for the "`DIGEST-MD5`" SASL mechanism type, specified
# in RFC2831(https://tools.ietf.org/html/rfc2831).  See Net::IMAP#authenticate.
#
# == Deprecated
#
# "+DIGEST-MD5+" has been deprecated by
# {RFC6331}[https://tools.ietf.org/html/rfc6331] and should not be relied on for
# security.  It is included for compatibility with existing servers.
class Net::IMAP::DigestMD5Authenticator
  def process(challenge)
    case @stage
    when STAGE_ONE
      @stage = STAGE_TWO
      sparams = {}
      c = StringScanner.new(challenge)
      while c.scan(/(?:\s*,)?\s*(\w+)=("(?:[^\\"]+|\\.)*"|[^,]+)\s*/)
        k, v = c[1], c[2]
        if v =~ /^"(.*)"$/
          v = $1
          if v =~ /,/
            v = v.split(',')
          end
        end
        sparams[k] = v
      end

      raise DataFormatError, "Bad Challenge: '#{challenge}'" unless c.rest.size == 0
      raise Error, "Server does not support auth (qop = #{sparams['qop'].join(',')})" unless sparams['qop'].include?("auth")

      response = {
        :nonce => sparams['nonce'],
        :username => @user,
        :realm => sparams['realm'],
        :cnonce => Digest::MD5.hexdigest("%.15f:%.15f:%d" % [Time.now.to_f, rand, Process.pid.to_s]),
        :'digest-uri' => 'imap/' + sparams['realm'],
        :qop => 'auth',
        :maxbuf => 65535,
        :nc => "%08d" % nc(sparams['nonce']),
        :charset => sparams['charset'],
      }

      response[:authzid] = @authname unless @authname.nil?

      # now, the real thing
      a0 = Digest::MD5.digest( [ response.values_at(:username, :realm), @password ].join(':') )

      a1 = [ a0, response.values_at(:nonce,:cnonce) ].join(':')
      a1 << ':' + response[:authzid] unless response[:authzid].nil?

      a2 = "AUTHENTICATE:" + response[:'digest-uri']
      a2 << ":00000000000000000000000000000000" if response[:qop] and response[:qop] =~ /^auth-(?:conf|int)$/

      response[:response] = Digest::MD5.hexdigest(
        [
          Digest::MD5.hexdigest(a1),
          response.values_at(:nonce, :nc, :cnonce, :qop),
          Digest::MD5.hexdigest(a2)
        ].join(':')
      )

      return response.keys.map {|key| qdval(key.to_s, response[key]) }.join(',')
    when STAGE_TWO
      @stage = nil
      # if at the second stage, return an empty string
      if challenge =~ /rspauth=/
        return ''
      else
        raise ResponseParseError, challenge
      end
    else
      raise ResponseParseError, challenge
    end
  end

  def initialize(user, password, authname = nil)
    @user, @password, @authname = user, password, authname
    @nc, @stage = {}, STAGE_ONE
  end

  private

  STAGE_ONE = :stage_one
  STAGE_TWO = :stage_two

  def nc(nonce)
    if @nc.has_key? nonce
      @nc[nonce] = @nc[nonce] + 1
    else
      @nc[nonce] = 1
    end
    return @nc[nonce]
  end

  # some responses need quoting
  def qdval(k, v)
    return if k.nil? or v.nil?
    if %w"username authzid realm nonce cnonce digest-uri qop".include? k
      v.gsub!(/([\\"])/, "\\\1")
      return '%s="%s"' % [k, v]
    else
      return '%s=%s' % [k, v]
    end
  end

  Net::IMAP.add_authenticator "DIGEST-MD5", self
end
