#include "rbs_extension.h"

#define RESET_TABLE_P(table) (table->size == 0)

id_table *alloc_empty_table(void) {
  id_table *table = malloc(sizeof(id_table));
  table->size = 10;
  table->count = 0;
  table->ids = calloc(10, sizeof(ID));

  return table;
}

id_table *alloc_reset_table(void) {
  id_table *table = malloc(sizeof(id_table));
  table->size = 0;

  return table;
}

id_table *parser_push_typevar_table(parserstate *state, bool reset) {
  if (reset) {
    id_table *table = alloc_reset_table();
    table->next = state->vars;
    state->vars = table;
  }

  id_table *table = alloc_empty_table();
  table->next = state->vars;
  state->vars = table;

  return table;
}

void parser_pop_typevar_table(parserstate *state) {
  id_table *table;

  if (state->vars) {
    table = state->vars;
    state->vars = table->next;
    free(table->ids);
    free(table);
  } else {
    rb_raise(rb_eRuntimeError, "Cannot pop empty table");
  }

  if (state->vars && RESET_TABLE_P(state->vars)) {
    table = state->vars;
    state->vars = table->next;
    free(table);
  }
}

void parser_insert_typevar(parserstate *state, ID id) {
  id_table *table = state->vars;

  if (RESET_TABLE_P(table)) {
    rb_raise(rb_eRuntimeError, "Cannot insert to reset table");
  }

  if (table->size == table->count) {
    // expand
    ID *ptr = table->ids;
    table->size += 10;
    table->ids = calloc(table->size, sizeof(ID));
    memcpy(table->ids, ptr, sizeof(ID) * table->count);
    free(ptr);
  }

  table->ids[table->count++] = id;
}

bool parser_typevar_member(parserstate *state, ID id) {
  id_table *table = state->vars;

  while (table && !RESET_TABLE_P(table)) {
    for (size_t i = 0; i < table->count; i++) {
      if (table->ids[i] == id) {
        return true;
      }
    }

    table = table->next;
  }

  return false;
}

void print_parser(parserstate *state) {
  printf("  current_token = %s (%d...%d)\n", token_type_str(state->current_token.type), state->current_token.range.start.char_pos, state->current_token.range.end.char_pos);
  printf("     next_token = %s (%d...%d)\n", token_type_str(state->next_token.type), state->next_token.range.start.char_pos, state->next_token.range.end.char_pos);
  printf("    next_token2 = %s (%d...%d)\n", token_type_str(state->next_token2.type), state->next_token2.range.start.char_pos, state->next_token2.range.end.char_pos);
  printf("    next_token3 = %s (%d...%d)\n", token_type_str(state->next_token3.type), state->next_token3.range.start.char_pos, state->next_token3.range.end.char_pos);
}

void parser_advance(parserstate *state) {
  state->current_token = state->next_token;
  state->next_token = state->next_token2;
  state->next_token2 = state->next_token3;

  while (true) {
    if (state->next_token3.type == pEOF) {
      break;
    }

    state->next_token3 = rbsparser_next_token(state->lexstate);

    if (state->next_token3.type == tCOMMENT) {
      // skip
    } else if (state->next_token3.type == tLINECOMMENT) {
      insert_comment_line(state, state->next_token3);
    } else {
      break;
    }
  }
}

/**
 * Advance token if _next_ token is `type`.
 * Ensures one token advance and `state->current_token.type == type`, or current token not changed.
 *
 * @returns true if token advances, false otherwise.
 **/
bool parser_advance_if(parserstate *state, enum TokenType type) {
  if (state->next_token.type == type) {
    parser_advance(state);
    return true;
  } else {
    return false;
  }
}

void parser_assert(parserstate *state, enum TokenType type) {
  if (state->current_token.type != type) {
    raise_syntax_error(
      state,
      state->current_token,
      "expected a token `%s`",
      token_type_str(type)
    );
  }
}

void parser_advance_assert(parserstate *state, enum TokenType type) {
  parser_advance(state);
  parser_assert(state, type);
}

void print_token(token tok) {
  printf(
    "%s char=%d...%d\n",
    token_type_str(tok.type),
    tok.range.start.char_pos,
    tok.range.end.char_pos
  );
}

void insert_comment_line(parserstate *state, token tok) {
  int prev_line = tok.range.start.line - 1;

  comment *com = comment_get_comment(state->last_comment, prev_line);

  if (com) {
    comment_insert_new_line(com, tok);
  } else {
    state->last_comment = alloc_comment(tok, state->last_comment);
  }
}

VALUE get_comment(parserstate *state, int subject_line) {
  int comment_line = subject_line - 1;

  comment *com = comment_get_comment(state->last_comment, comment_line);

  if (com) {
    return comment_to_ruby(com, state->buffer);
  } else {
    return Qnil;
  }
}

comment *alloc_comment(token comment_token, comment *last_comment) {
  comment *new_comment = calloc(1, sizeof(comment));

  new_comment->next_comment = last_comment;

  new_comment->start = comment_token.range.start;
  new_comment->end = comment_token.range.end;

  new_comment->line_size = 0;
  new_comment->line_count = 0;

  comment_insert_new_line(new_comment, comment_token);

  return new_comment;
}

void free_comment(comment *com) {
  if (com->next_comment) {
    free_comment(com->next_comment);
  }

  free(com->tokens);
  free(com);
}

void comment_insert_new_line(comment *com, token comment_token) {
  if (com->line_count == 0) {
    com->start = comment_token.range.start;
  }

  if (com->line_count == com->line_size) {
    com->line_size += 10;

    if (com->tokens) {
      token *p = com->tokens;
      com->tokens = calloc(com->line_size, sizeof(token));
      memcpy(com->tokens, p, sizeof(token) * com->line_count);
      free(p);
    } else {
      com->tokens = calloc(com->line_size, sizeof(token));
    }
  }

  com->tokens[com->line_count++] = comment_token;
  com->end = comment_token.range.end;
}

comment *comment_get_comment(comment *com, int line) {
  if (com == NULL) {
    return NULL;
  }

  if (com->end.line < line) {
    return NULL;
  }

  if (com->end.line == line) {
    return com;
  }

  return comment_get_comment(com->next_comment, line);
}

VALUE comment_to_ruby(comment *com, VALUE buffer) {
  VALUE content = rb_funcall(buffer, rb_intern("content"), 0);
  rb_encoding *enc = rb_enc_get(content);
  VALUE string = rb_enc_str_new_cstr("", enc);

  int hash_bytes = rb_enc_codelen('#', enc);
  int space_bytes = rb_enc_codelen(' ', enc);

  for (size_t i = 0; i < com->line_count; i++) {
    token tok = com->tokens[i];

    char *comment_start = RSTRING_PTR(content) + tok.range.start.byte_pos + hash_bytes;
    int comment_bytes = RANGE_BYTES(tok.range) - hash_bytes;
    unsigned char c = rb_enc_mbc_to_codepoint(comment_start, RSTRING_END(content), enc);

    if (c == ' ') {
      comment_start += space_bytes;
      comment_bytes -= space_bytes;
    }

    rb_str_cat(string, comment_start, comment_bytes);
    rb_str_cat_cstr(string, "\n");
  }

  return rbs_ast_comment(
    string,
    rbs_location_pp(buffer, &com->start, &com->end)
  );
}

parserstate *alloc_parser(VALUE buffer, int line, int column, VALUE variables) {
  VALUE string = rb_funcall(buffer, rb_intern("content"), 0);

  lexstate *lexer = calloc(1, sizeof(lexstate));
  lexer->string = string;
  lexer->current.line = line;
  lexer->current.column = column;
  lexer->start = lexer->current;
  lexer->first_token_of_line = lexer->current.column == 0;

  parserstate *parser = calloc(1, sizeof(parserstate));
  parser->lexstate = lexer;
  parser->buffer = buffer;
  parser->current_token = NullToken;
  parser->next_token = NullToken;
  parser->next_token2 = NullToken;
  parser->next_token3 = NullToken;

  parser_advance(parser);
  parser_advance(parser);
  parser_advance(parser);

  if (!NIL_P(variables)) {
    parser_push_typevar_table(parser, true);

    for (long i = 0; i < rb_array_len(variables); i++) {
      VALUE index = INT2FIX(i);
      VALUE symbol = rb_ary_aref(1, &index, variables);
      parser_insert_typevar(parser, SYM2ID(symbol));
    }
  }

  return parser;
}

void free_parser(parserstate *parser) {
  free(parser->lexstate);
  if (parser->last_comment) {
    free_comment(parser->last_comment);
  }
  free(parser);
}
