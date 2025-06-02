#ifndef RBS__PARSERSTATE_H
#define RBS__PARSERSTATE_H

#include <stdbool.h>

#include "lexer.h"
#include "location.h"

/**
 * id_table represents a set of IDs.
 * This is used to manage the set of bound variables.
 * */
typedef struct id_table {
  size_t size;
  size_t count;
  ID *ids;
  struct id_table *next;
} id_table;

/**
 * comment represents a sequence of comment lines.
 *
 *     # Comment for the method.
 *     #
 *     # ```rb
 *     # object.foo()  # Do something
 *     # ```
 *     #
 *     def foo: () -> void
 *
 * A comment object represents the six lines of comments.
 * */
typedef struct comment {
  position start;
  position end;

  size_t line_size;
  size_t line_count;
  token *tokens;

  struct comment *next_comment;
} comment;

/**
 * An RBS parser is a LL(3) parser.
 * */
typedef struct {
  lexstate *lexstate;

  token current_token;
  token next_token;       /* The first lookahead token */
  token next_token2;      /* The second lookahead token */
  token next_token3;      /* The third lookahead token */
  VALUE buffer;

  id_table *vars;         /* Known type variables */
  comment *last_comment;  /* Last read comment */
} parserstate;

comment *alloc_comment(token comment_token, comment *last_comment);
void free_comment(comment *com);
void comment_insert_new_line(comment *com, token comment_token);
comment *comment_get_comment(comment *com, int line);
VALUE comment_to_ruby(comment *com, VALUE buffer);

/**
 * Insert new table entry.
 * Setting `reset` inserts a _reset_ entry, which stops searching.
 *
 * ```
 * class Foo[A]
 *          ^^^                      <= push new table with reset
 *   def foo: [B] () -> [A, B]
 *            ^^^                    <= push new table without reset
 *
 *   class Baz[C]
 *            ^^^                    <= push new table with reset
 *   end
 * end
 * ```
 * */
id_table *parser_push_typevar_table(parserstate *state, bool reset);
void parser_pop_typevar_table(parserstate *state);
/**
 * Insert new type variable into the latest table.
 * */
void parser_insert_typevar(parserstate *state, ID id);

/**
 * Returns true if given type variable is recorded in the table.
 * If not found, it goes one table up, if it's not a reset table.
 * Or returns false, if it's a reset table.
 * */
bool parser_typevar_member(parserstate *state, ID id);

/**
 * Allocate new parserstate object.
 *
 * ```
 * alloc_parser(buffer, 0, 1, variables)    // New parserstate with variables
 * alloc_parser(buffer, 3, 5, Qnil)         // New parserstate without variables
 * ```
 * */
parserstate *alloc_parser(VALUE buffer, int line, int column, VALUE variables);
void free_parser(parserstate *parser);
/**
 * Advance one token.
 * */
void parser_advance(parserstate *state);

/**
 * @brief Raises an exception if `current_token->type != type`.
 *
 * @param state
 * @param type
 */
void parser_assert(parserstate *state, enum TokenType type);

/**
 * Advance one token, and assert the current token type.
 * Raises an exception if `current_token->type != type`.
 * */
void parser_advance_assert(parserstate *state, enum TokenType type);

/**
 * Advance one token if the next_token is a token of the type.
 * */
bool parser_advance_if(parserstate *state, enum TokenType type);
void print_parser(parserstate *state);

/**
 * Insert new comment line token.
 * */
void insert_comment_line(parserstate *state, token token);

/**
 * Returns a RBS::Comment object associated with an subject at `subject_line`.
 *
 * ```rbs
 * # Comment1
 * class Foo           # This is the subject line for Comment1
 *
 *   # Comment2
 *   %a{annotation}    # This is the subject line for Comment2
 *   def foo: () -> void
 * end
 * ```
 * */
VALUE get_comment(parserstate *state, int subject_line);

#endif
