module URI
  # :stopdoc:
  VERSION_CODE = '001201'.freeze
  VERSION = VERSION_CODE.scan(/../).collect{|n| n.to_i}.join('.').freeze
  # :startdoc:
end
