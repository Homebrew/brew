# frozen_string_literal: false
#
# HTTP/1.1 methods --- RFC2616
#

# See Net::HTTPGenericRequest for attributes and methods.
# See Net::HTTP for usage examples.
class Net::HTTP::Get < Net::HTTPRequest
  METHOD = 'GET'
  REQUEST_HAS_BODY  = false
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
# See Net::HTTP for usage examples.
class Net::HTTP::Head < Net::HTTPRequest
  METHOD = 'HEAD'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = false
end

# See Net::HTTPGenericRequest for attributes and methods.
# See Net::HTTP for usage examples.
class Net::HTTP::Post < Net::HTTPRequest
  METHOD = 'POST'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
# See Net::HTTP for usage examples.
class Net::HTTP::Put < Net::HTTPRequest
  METHOD = 'PUT'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
# See Net::HTTP for usage examples.
class Net::HTTP::Delete < Net::HTTPRequest
  METHOD = 'DELETE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Options < Net::HTTPRequest
  METHOD = 'OPTIONS'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Trace < Net::HTTPRequest
  METHOD = 'TRACE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

#
# PATCH method --- RFC5789
#

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Patch < Net::HTTPRequest
  METHOD = 'PATCH'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

#
# WebDAV methods --- RFC2518
#

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Propfind < Net::HTTPRequest
  METHOD = 'PROPFIND'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Proppatch < Net::HTTPRequest
  METHOD = 'PROPPATCH'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Mkcol < Net::HTTPRequest
  METHOD = 'MKCOL'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Copy < Net::HTTPRequest
  METHOD = 'COPY'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Move < Net::HTTPRequest
  METHOD = 'MOVE'
  REQUEST_HAS_BODY = false
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Lock < Net::HTTPRequest
  METHOD = 'LOCK'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

# See Net::HTTPGenericRequest for attributes and methods.
class Net::HTTP::Unlock < Net::HTTPRequest
  METHOD = 'UNLOCK'
  REQUEST_HAS_BODY = true
  RESPONSE_HAS_BODY = true
end

