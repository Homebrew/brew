#ifndef RBS_LOCATION_H
#define RBS_LOCATION_H

#include "ruby.h"
#include "lexer.h"

/**
 * RBS::Location class
 * */
extern VALUE RBS_Location;

typedef struct rbs_loc_list {
  ID name;
  range rg;
  struct rbs_loc_list *next;
} rbs_loc_list;

typedef struct {
  VALUE buffer;
  range rg;
  rbs_loc_list *requireds;
  rbs_loc_list *optionals;
} rbs_loc;

/**
 * Returns new RBS::Location object, with given buffer and range.
 * */
VALUE rbs_new_location(VALUE buffer, range rg);

/**
 * Return rbs_loc assiciated with the RBS::Location object.
 * */
rbs_loc *rbs_check_location(VALUE location);

/**
 * Add a required child range with given name.
 * */
void rbs_loc_add_required_child(rbs_loc *loc, ID name, range r);

/**
 * Add an optional child range with given name.
 * */
void rbs_loc_add_optional_child(rbs_loc *loc, ID name, range r);

/**
 * Returns RBS::Location object with start/end positions.
 *
 * @param start_pos
 * @param end_pos
 * @return New RSS::Location object.
 * */
VALUE rbs_location_pp(VALUE buffer, const position *start_pos, const position *end_pos);

/**
 * Define RBS::Location class.
 * */
void rbs__init_location();

#endif
