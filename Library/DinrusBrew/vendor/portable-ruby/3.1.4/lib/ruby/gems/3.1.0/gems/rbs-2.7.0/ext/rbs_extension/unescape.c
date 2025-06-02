#include "rbs_extension.h"

static VALUE DQ_REGEXP = 0;
static VALUE SQ_REGEXP = 0;
static VALUE HASH = 0;

static const char *dq_regexp_str = "\\\\[abefnrstv\"\\\\]";
static const char *sq_regexp_str = "\\\\[\'\\\\]";

static ID gsub = 0;

void rbs_unescape_string(VALUE string, bool dq_string) {
  if (!DQ_REGEXP) {
    DQ_REGEXP = rb_reg_new(dq_regexp_str, strlen(dq_regexp_str), 0);
    rb_global_variable(&DQ_REGEXP);
  }

  if (!SQ_REGEXP) {
    SQ_REGEXP = rb_reg_new(sq_regexp_str, strlen(sq_regexp_str), 0);
    rb_global_variable(&SQ_REGEXP);
  }

  if (!gsub) {
    gsub = rb_intern("gsub!");
  }

  if (!HASH) {
    HASH = rb_hash_new();
    rb_global_variable(&HASH);
    rb_hash_aset(HASH, rb_str_new_literal("\\a"), rb_str_new_literal("\a"));
    rb_hash_aset(HASH, rb_str_new_literal("\\b"), rb_str_new_literal("\b"));
    rb_hash_aset(HASH, rb_str_new_literal("\\e"), rb_str_new_literal("\033"));
    rb_hash_aset(HASH, rb_str_new_literal("\\f"), rb_str_new_literal("\f"));
    rb_hash_aset(HASH, rb_str_new_literal("\\n"), rb_str_new_literal("\n"));
    rb_hash_aset(HASH, rb_str_new_literal("\\r"), rb_str_new_literal("\r"));
    rb_hash_aset(HASH, rb_str_new_literal("\\s"), rb_str_new_literal(" "));
    rb_hash_aset(HASH, rb_str_new_literal("\\t"), rb_str_new_literal("\t"));
    rb_hash_aset(HASH, rb_str_new_literal("\\v"), rb_str_new_literal("\v"));
    rb_hash_aset(HASH, rb_str_new_literal("\\\""), rb_str_new_literal("\""));
    rb_hash_aset(HASH, rb_str_new_literal("\\\'"), rb_str_new_literal("'"));
    rb_hash_aset(HASH, rb_str_new_literal("\\\\"), rb_str_new_literal("\\"));
  }

  rb_funcall(string, gsub, 2, dq_string ? DQ_REGEXP : SQ_REGEXP, HASH);
}

VALUE rbs_unquote_string(parserstate *state, range rg, int offset_bytes) {
  VALUE string = state->lexstate->string;
  rb_encoding *enc = rb_enc_get(string);

  unsigned int first_char = rb_enc_mbc_to_codepoint(
    RSTRING_PTR(string) + rg.start.byte_pos + offset_bytes,
    RSTRING_END(string),
    enc
  );

  int byte_length = rg.end.byte_pos - rg.start.byte_pos - offset_bytes;

  if (first_char == '"' || first_char == '\'' || first_char == '`') {
    int bs = rb_enc_codelen(first_char, enc);
    offset_bytes += bs;
    byte_length -= 2 * bs;
  }

  char *buffer = RSTRING_PTR(state->lexstate->string) + rg.start.byte_pos + offset_bytes;
  VALUE str = rb_enc_str_new(buffer, byte_length, enc);

  rbs_unescape_string(str, first_char == '\"');

  return str;
}

