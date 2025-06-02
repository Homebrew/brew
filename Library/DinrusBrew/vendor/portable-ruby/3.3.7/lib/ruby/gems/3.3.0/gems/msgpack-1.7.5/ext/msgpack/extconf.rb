require 'mkmf'

have_func("rb_enc_interned_str", "ruby.h") # Ruby 3.0+
have_func("rb_hash_new_capa", "ruby.h") # Ruby 3.2+
have_func("rb_proc_call_with_block", "ruby.h") # CRuby (TruffleRuby doesn't have it)

append_cflags([
  "-fvisibility=hidden",
  "-I..",
  "-Wall",
  "-O3",
  "-std=gnu99"
])
append_cflags(RbConfig::CONFIG["debugflags"]) if RbConfig::CONFIG["debugflags"]

append_cflags("-DRUBY_DEBUG=1") if ENV["MSGPACK_DEBUG"]

if RUBY_VERSION.start_with?('3.0.') && RUBY_VERSION <= '3.0.5'
  # https://bugs.ruby-lang.org/issues/18772
  append_cflags("-DRB_ENC_INTERNED_STR_NULL_CHECK=1")
end

# checking if Hash#[]= (rb_hash_aset) dedupes string keys (Ruby 2.6+)
h = {}
x = {}
r = rand.to_s
h[%W(#{r}).join('')] = :foo
x[%W(#{r}).join('')] = :foo
if x.keys[0].equal?(h.keys[0])
  append_cflags("-DHASH_ASET_DEDUPE=1")
else
  append_cflags("-DHASH_ASET_DEDUPE=0")
end

# checking if String#-@ (str_uminus) directly interns frozen strings... ' (Ruby 3.0+)
begin
  s = rand.to_s.freeze
  if (-s).equal?(s) && (-s.dup).equal?(s)
    append_cflags("-DSTR_UMINUS_DEDUPE_FROZEN=1")
  else
    append_cflags("-DSTR_UMINUS_DEDUPE_FROZEN=0")
  end
rescue NoMethodError
  append_cflags("-DSTR_UMINUS_DEDUPE_FROZEN=0")
end

if warnflags = CONFIG['warnflags']
  warnflags.slice!(/ -Wdeclaration-after-statement/)
end

create_makefile('msgpack/msgpack')
