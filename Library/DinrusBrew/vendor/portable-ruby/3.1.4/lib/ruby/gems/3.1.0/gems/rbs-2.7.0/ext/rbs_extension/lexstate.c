#include "rbs_extension.h"

static const char *RBS_TOKENTYPE_NAMES[] = {
  "NullType",
  "pEOF",
  "ErrorToken",

  "pLPAREN",          /* ( */
  "pRPAREN",          /* ) */
  "pCOLON",           /* : */
  "pCOLON2",          /* :: */
  "pLBRACKET",        /* [ */
  "pRBRACKET",        /* ] */
  "pLBRACE",          /* { */
  "pRBRACE",          /* } */
  "pHAT",             /* ^ */
  "pARROW",           /* -> */
  "pFATARROW",        /* => */
  "pCOMMA",           /* , */
  "pBAR",             /* | */
  "pAMP",             /* & */
  "pSTAR",            /* * */
  "pSTAR2",           /* ** */
  "pDOT",             /* . */
  "pDOT3",            /* ... */
  "pBANG",            /* ! */
  "pQUESTION",        /* ? */
  "pLT",              /* < */
  "pEQ",              /* = */

  "kALIAS",           /* alias */
  "kATTRACCESSOR",    /* attr_accessor */
  "kATTRREADER",      /* attr_reader */
  "kATTRWRITER",      /* attr_writer */
  "kBOOL",            /* bool */
  "kBOT",             /* bot */
  "kCLASS",           /* class */
  "kDEF",             /* def */
  "kEND",             /* end */
  "kEXTEND",          /* extend */
  "kFALSE",           /* kFALSE */
  "kIN",              /* in */
  "kINCLUDE",         /* include */
  "kINSTANCE",        /* instance */
  "kINTERFACE",       /* interface */
  "kMODULE",          /* module */
  "kNIL",             /* nil */
  "kOUT",             /* out */
  "kPREPEND",         /* prepend */
  "kPRIVATE",         /* private */
  "kPUBLIC",          /* public */
  "kSELF",            /* self */
  "kSINGLETON",       /* singleton */
  "kTOP",             /* top */
  "kTRUE",            /* true */
  "kTYPE",            /* type */
  "kUNCHECKED",       /* unchecked */
  "kUNTYPED",         /* untyped */
  "kVOID",            /* void */

  "tLIDENT",          /* Identifiers starting with lower case */
  "tUIDENT",          /* Identifiers starting with upper case */
  "tULIDENT",         /* Identifiers starting with `_` */
  "tULLIDENT",
  "tGIDENT",          /* Identifiers starting with `$` */
  "tAIDENT",          /* Identifiers starting with `@` */
  "tA2IDENT",         /* Identifiers starting with `@@` */
  "tBANGIDENT",
  "tEQIDENT",
  "tQIDENT",          /* Quoted identifier */
  "pAREF_OPR",        /* [] */
  "tOPERATOR",        /* Operator identifier */

  "tCOMMENT",
  "tLINECOMMENT",

  "tDQSTRING",        /* Double quoted string */
  "tSQSTRING",        /* Single quoted string */
  "tINTEGER",         /* Integer */
  "tSYMBOL",          /* Symbol */
  "tDQSYMBOL",
  "tSQSYMBOL",
  "tANNOTATION",      /* Annotation */
};

token NullToken = { NullType };
position NullPosition = { -1, -1, -1, -1 };
range NULL_RANGE = { { -1, -1, -1, -1 }, { -1, -1, -1, -1 } };

const char *token_type_str(enum TokenType type) {
  return RBS_TOKENTYPE_NAMES[type];
}

int token_chars(token tok) {
  return tok.range.end.char_pos - tok.range.start.char_pos;
}

int token_bytes(token tok) {
  return RANGE_BYTES(tok.range);
}

unsigned int peek(lexstate *state) {
  unsigned int c = rb_enc_mbc_to_codepoint(RSTRING_PTR(state->string) + state->current.byte_pos, RSTRING_END(state->string), rb_enc_get(state->string));
  state->last_char = c;
  return c;
}

token next_token(lexstate *state, enum TokenType type) {
  token t;

  t.type = type;
  t.range.start = state->start;
  t.range.end = state->current;
  state->start = state->current;
  state->first_token_of_line = false;

  return t;
}

void skip(lexstate *state) {
  if (!state->last_char) {
    peek(state);
  }
  int byte_len = rb_enc_codelen(state->last_char, rb_enc_get(state->string));

  state->current.char_pos += 1;
  state->current.byte_pos += byte_len;

  if (state->last_char == '\n') {
    state->current.line += 1;
    state->current.column = 0;
    state->first_token_of_line = true;
  } else {
    state->current.column += 1;
  }
}

void skipn(lexstate *state, size_t size) {
  for (size_t i = 0; i < size; i ++) {
    skip(state);
  }
}

char *peek_token(lexstate *state, token tok) {
  return RSTRING_PTR(state->string) + tok.range.start.byte_pos;
}
