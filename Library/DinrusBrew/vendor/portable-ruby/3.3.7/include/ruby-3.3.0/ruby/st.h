/* This is a public domain general purpose hash table package
   originally written by Peter Moore @ UCB.

   The hash table data structures were redesigned and the package was
   rewritten by Vladimir Makarov <vmakarov@redhat.com>.  */

#ifndef RUBY_ST_H
#define RUBY_ST_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include "ruby/defines.h"

RUBY_SYMBOL_EXPORT_BEGIN

#if SIZEOF_LONG == SIZEOF_VOIDP
typedef unsigned long st_data_t;
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
typedef unsigned LONG_LONG st_data_t;
#else
# error ---->> st.c requires sizeof(void*) == sizeof(long) or sizeof(LONG_LONG) to be compiled. <<----
#endif
#define ST_DATA_T_DEFINED

#ifndef CHAR_BIT
# ifdef HAVE_LIMITS_H
#  include <limits.h>
# else
#  define CHAR_BIT 8
# endif
#endif
#ifndef _
# define _(args) args
#endif
#ifndef ANYARGS
# ifdef __cplusplus
#   define ANYARGS ...
# else
#   define ANYARGS
# endif
#endif

typedef struct st_table st_table;

typedef st_data_t st_index_t;

/* Maximal value of unsigned integer type st_index_t.  */
#define MAX_ST_INDEX_VAL (~(st_index_t) 0)

typedef int st_compare_func(st_data_t, st_data_t);
typedef st_index_t st_hash_func(st_data_t);

typedef char st_check_for_sizeof_st_index_t[SIZEOF_VOIDP == (int)sizeof(st_index_t) ? 1 : -1];
#define SIZEOF_ST_INDEX_T SIZEOF_VOIDP

struct st_hash_type {
    int (*compare)(st_data_t, st_data_t); /* st_compare_func* */
    st_index_t (*hash)(st_data_t);        /* st_hash_func* */
};

#define ST_INDEX_BITS (SIZEOF_ST_INDEX_T * CHAR_BIT)

#if defined(HAVE_BUILTIN___BUILTIN_CHOOSE_EXPR) && defined(HAVE_BUILTIN___BUILTIN_TYPES_COMPATIBLE_P)
# define ST_DATA_COMPATIBLE_P(type) \
   __builtin_choose_expr(__builtin_types_compatible_p(type, st_data_t), 1, 0)
#else
# define ST_DATA_COMPATIBLE_P(type) 0
#endif

typedef struct st_table_entry st_table_entry;

struct st_table_entry; /* defined in st.c */

struct st_table {
    /* Cached features of the table -- see st.c for more details.  */
    unsigned char entry_power, bin_power, size_ind;
    /* How many times the table was rebuilt.  */
    unsigned int rebuilds_num;
    const struct st_hash_type *type;
    /* Number of entries currently in the table.  */
    st_index_t num_entries;
    /* Array of bins used for access by keys.  */
    st_index_t *bins;
    /* Start and bound index of entries in array entries.
       entries_starts and entries_bound are in interval
       [0,allocated_entries].  */
    st_index_t entries_start, entries_bound;
    /* Array of size 2^entry_power.  */
    st_table_entry *entries;
};

#define st_is_member(table,key) st_lookup((table),(key),(st_data_t *)0)

enum st_retval {ST_CONTINUE, ST_STOP, ST_DELETE, ST_CHECK, ST_REPLACE};

size_t rb_st_table_size(const struct st_table *tbl);
#define st_table_size rb_st_table_size
st_table *rb_st_init_table(const struct st_hash_type *);
#define st_init_table rb_st_init_table
st_table *rb_st_init_table_with_size(const struct st_hash_type *, st_index_t);
#define st_init_table_with_size rb_st_init_table_with_size
st_table *rb_st_init_existing_table_with_size(st_table *tab, const struct st_hash_type *type, st_index_t size);
#define st_init_existing_table_with_size rb_st_init_existing_table_with_size
st_table *rb_st_init_numtable(void);
#define st_init_numtable rb_st_init_numtable
st_table *rb_st_init_numtable_with_size(st_index_t);
#define st_init_numtable_with_size rb_st_init_numtable_with_size
st_table *rb_st_init_strtable(void);
#define st_init_strtable rb_st_init_strtable
st_table *rb_st_init_strtable_with_size(st_index_t);
#define st_init_strtable_with_size rb_st_init_strtable_with_size
st_table *rb_st_init_strcasetable(void);
#define st_init_strcasetable rb_st_init_strcasetable
st_table *rb_st_init_strcasetable_with_size(st_index_t);
#define st_init_strcasetable_with_size rb_st_init_strcasetable_with_size
int rb_st_delete(st_table *, st_data_t *, st_data_t *); /* returns 0:notfound 1:deleted */
#define st_delete rb_st_delete
int rb_st_delete_safe(st_table *, st_data_t *, st_data_t *, st_data_t);
#define st_delete_safe rb_st_delete_safe
int rb_st_shift(st_table *, st_data_t *, st_data_t *); /* returns 0:notfound 1:deleted */
#define st_shift rb_st_shift
int rb_st_insert(st_table *, st_data_t, st_data_t);
#define st_insert rb_st_insert
int rb_st_insert2(st_table *, st_data_t, st_data_t, st_data_t (*)(st_data_t));
#define st_insert2 rb_st_insert2
int rb_st_lookup(st_table *, st_data_t, st_data_t *);
#define st_lookup rb_st_lookup
int rb_st_get_key(st_table *, st_data_t, st_data_t *);
#define st_get_key rb_st_get_key
typedef int st_update_callback_func(st_data_t *key, st_data_t *value, st_data_t arg, int existing);
/* *key may be altered, but must equal to the old key, i.e., the
 * results of hash() are same and compare() returns 0, otherwise the
 * behavior is undefined */
int rb_st_update(st_table *table, st_data_t key, st_update_callback_func *func, st_data_t arg);
#define st_update rb_st_update
typedef int st_foreach_callback_func(st_data_t, st_data_t, st_data_t);
typedef int st_foreach_check_callback_func(st_data_t, st_data_t, st_data_t, int);
int rb_st_foreach_with_replace(st_table *tab, st_foreach_check_callback_func *func, st_update_callback_func *replace, st_data_t arg);
#define st_foreach_with_replace rb_st_foreach_with_replace
int rb_st_foreach(st_table *, st_foreach_callback_func *, st_data_t);
#define st_foreach rb_st_foreach
int rb_st_foreach_check(st_table *, st_foreach_check_callback_func *, st_data_t, st_data_t);
#define st_foreach_check rb_st_foreach_check
st_index_t rb_st_keys(st_table *table, st_data_t *keys, st_index_t size);
#define st_keys rb_st_keys
st_index_t rb_st_keys_check(st_table *table, st_data_t *keys, st_index_t size, st_data_t never);
#define st_keys_check rb_st_keys_check
st_index_t rb_st_values(st_table *table, st_data_t *values, st_index_t size);
#define st_values rb_st_values
st_index_t rb_st_values_check(st_table *table, st_data_t *values, st_index_t size, st_data_t never);
#define st_values_check rb_st_values_check
void rb_st_add_direct(st_table *, st_data_t, st_data_t);
#define st_add_direct rb_st_add_direct
void rb_st_free_table(st_table *);
#define st_free_table rb_st_free_table
void rb_st_cleanup_safe(st_table *, st_data_t);
#define st_cleanup_safe rb_st_cleanup_safe
void rb_st_clear(st_table *);
#define st_clear rb_st_clear
st_table *rb_st_replace(st_table *new_tab, st_table *old_tab);
#define st_replace rb_st_replace
st_table *rb_st_copy(st_table *);
#define st_copy rb_st_copy
CONSTFUNC(int rb_st_numcmp(st_data_t, st_data_t));
#define st_numcmp rb_st_numcmp
CONSTFUNC(st_index_t rb_st_numhash(st_data_t));
#define st_numhash rb_st_numhash
PUREFUNC(int rb_st_locale_insensitive_strcasecmp(const char *s1, const char *s2));
#define st_locale_insensitive_strcasecmp rb_st_locale_insensitive_strcasecmp
PUREFUNC(int rb_st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n));
#define st_locale_insensitive_strncasecmp rb_st_locale_insensitive_strncasecmp
#define st_strcasecmp rb_st_locale_insensitive_strcasecmp
#define st_strncasecmp rb_st_locale_insensitive_strncasecmp
PUREFUNC(size_t rb_st_memsize(const st_table *));
#define st_memsize rb_st_memsize
PUREFUNC(st_index_t rb_st_hash(const void *ptr, size_t len, st_index_t h));
#define st_hash rb_st_hash
CONSTFUNC(st_index_t rb_st_hash_uint32(st_index_t h, uint32_t i));
#define st_hash_uint32 rb_st_hash_uint32
CONSTFUNC(st_index_t rb_st_hash_uint(st_index_t h, st_index_t i));
#define st_hash_uint rb_st_hash_uint
CONSTFUNC(st_index_t rb_st_hash_end(st_index_t h));
#define st_hash_end rb_st_hash_end
CONSTFUNC(st_index_t rb_st_hash_start(st_index_t h));
#define st_hash_start(h) ((st_index_t)(h))

void rb_hash_bulk_insert_into_st_table(long, const VALUE *, VALUE);

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_ST_H */
