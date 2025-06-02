#include <stdbool.h>

#include "ruby.h"
#include "ruby/re.h"
#include "ruby/encoding.h"

#include "lexer.h"
#include "parser.h"
#include "constants.h"
#include "ruby_objs.h"

/**
 * Unescape escape sequences in the given string inplace:
 *
 *   '\\n' => "\n"
 *
 * */
void rbs_unescape_string(VALUE string, bool dq_string);

/**
 * Receives `parserstate` and `range`, which represents a string token or symbol token, and returns a string VALUE.
 *
 *    Input token | Output string
 *    ------------+-------------
 *    "foo\\n"    | foo\n
 *    'foo'       | foo
 *    `bar`       | bar
 *    :"baz\\t"   | baz\t
 *    :'baz'      | baz
 * */
VALUE rbs_unquote_string(parserstate *state, range rg, int offset_bytes);

/**
 * Raises RBS::ParsingError on `tok` with message constructed with given `fmt`.
 *
 * ```
 * foo.rbs:11:21...11:25: Syntax error: {message}, token=`{tok source}` ({tok type})
 * ```
 * */
PRINTF_ARGS(NORETURN(void) raise_syntax_error(parserstate *state, token tok, const char *fmt, ...), 3, 4);
