Searcher = function(data) {
  this.data = data;
  this.handlers = [];
}

Searcher.prototype = new function() {
  // search is performed in chunks of 1000 for non-blocking user input
  var CHUNK_SIZE = 1000;
  // do not try to find more than 100 results
  var MAX_RESULTS = 100;
  var huid = 1;
  var suid = 1;
  var runs = 0;

  this.find = function(query) {
    var queries = splitQuery(query);
    var regexps = buildRegexps(queries);
    var highlighters = buildHilighters(queries);
    var state = { from: 0, pass: 0, limit: MAX_RESULTS, n: suid++};
    var _this = this;

    this.currentSuid = state.n;

    if (!query) return;

    var run = function() {
      // stop current search thread if new search started
      if (state.n != _this.currentSuid) return;

      var results =
        performSearch(_this.data, regexps, queries, highlighters, state);
      var hasMore = (state.limit > 0 && state.pass < 4);

      triggerResults.call(_this, results, !hasMore);
      if (hasMore) {
        setTimeout(run, 2);
      }
      runs++;
    };
    runs = 0;

    // start search thread
    run();
  }

  /*  ----- Events ------  */
  this.ready = function(fn) {
    fn.huid = huid;
    this.handlers.push(fn);
  }

  /*  ----- Utilities ------  */
  function splitQuery(query) {
    return query.split(/(\s+|::?|\(\)?)/).filter(function(string) {
      return string.match(/\S/);
    });
  }

  function buildRegexps(queries) {
    return queries.map(function(query) {
      return new RegExp(query.replace(/(.)/g, '([$1])([^$1]*?)'), 'i');
    });
  }

  function buildHilighters(queries) {
    return queries.map(function(query) {
      return query.split('').map(function(l, i) {
        return '\u0001$' + (i*2+1) + '\u0002$' + (i*2+2);
      }).join('');
    });
  }

  // function longMatchRegexp(index, longIndex, regexps) {
  //     for (var i = regexps.length - 1; i >= 0; i--){
  //         if (!index.match(regexps[i]) && !longIndex.match(regexps[i])) return false;
  //     };
  //     return true;
  // }


  /*  ----- Mathchers ------  */

  /*
   * This record matches if the index starts with queries[0] and the record
   * matches all of the regexps
   */
  function matchPassBeginning(index, longIndex, queries, regexps) {
    if (index.indexOf(queries[0]) != 0) return false;
    for (var i=1, l = regexps.length; i < l; i++) {
      if (!index.match(regexps[i]) && !longIndex.match(regexps[i]))
        return false;
    };
    return true;
  }

  /*
   * This record matches if the longIndex starts with queries[0] and the
   * longIndex matches all of the regexps
   */
  function matchPassLongIndex(index, longIndex, queries, regexps) {
    if (longIndex.indexOf(queries[0]) != 0) return false;
    for (var i=1, l = regexps.length; i < l; i++) {
      if (!longIndex.match(regexps[i]))
        return false;
    };
    return true;
  }

  /*
   * This record matches if the index contains queries[0] and the record
   * matches all of the regexps
   */
  function matchPassContains(index, longIndex, queries, regexps) {
    if (index.indexOf(queries[0]) == -1) return false;
    for (var i=1, l = regexps.length; i < l; i++) {
      if (!index.match(regexps[i]) && !longIndex.match(regexps[i]))
        return false;
    };
    return true;
  }

  /*
   * This record matches if regexps[0] matches the index and the record
   * matches all of the regexps
   */
  function matchPassRegexp(index, longIndex, queries, regexps) {
    if (!index.match(regexps[0])) return false;
    for (var i=1, l = regexps.length; i < l; i++) {
      if (!index.match(regexps[i]) && !longIndex.match(regexps[i]))
        return false;
    };
    return true;
  }


  /*  ----- Highlighters ------  */
  function highlightRegexp(info, queries, regexps, highlighters) {
    var result = createResult(info);
    for (var i=0, l = regexps.length; i < l; i++) {
      result.title = result.title.replace(regexps[i], highlighters[i]);
      result.namespace = result.namespace.replace(regexps[i], highlighters[i]);
    };
    return result;
  }

  function hltSubstring(string, pos, length) {
    return string.substring(0, pos) + '\u0001' + string.substring(pos, pos + length) + '\u0002' + string.substring(pos + length);
  }

  function highlightQuery(info, queries, regexps, highlighters) {
    var result = createResult(info);
    var pos = 0;
    var lcTitle = result.title.toLowerCase();

    pos = lcTitle.indexOf(queries[0]);
    if (pos != -1) {
      result.title = hltSubstring(result.title, pos, queries[0].length);
    }

    result.namespace = result.namespace.replace(regexps[0], highlighters[0]);
    for (var i=1, l = regexps.length; i < l; i++) {
      result.title = result.title.replace(regexps[i], highlighters[i]);
      result.namespace = result.namespace.replace(regexps[i], highlighters[i]);
    };
    return result;
  }

  function createResult(info) {
    var result = {};
    result.title = info[0];
    result.namespace = info[1];
    result.path = info[2];
    result.params = info[3];
    result.snippet = info[4];
    result.badge = info[6];
    return result;
  }

  /*  ----- Searching ------  */
  function performSearch(data, regexps, queries, highlighters, state) {
    var searchIndex = data.searchIndex;
    var longSearchIndex = data.longSearchIndex;
    var info = data.info;
    var result = [];
    var i = state.from;
    var l = searchIndex.length;
    var togo = CHUNK_SIZE;
    var matchFunc, hltFunc;

    while (state.pass < 4 && state.limit > 0 && togo > 0) {
      if (state.pass == 0) {
        matchFunc = matchPassBeginning;
        hltFunc = highlightQuery;
      } else if (state.pass == 1) {
        matchFunc = matchPassLongIndex;
        hltFunc = highlightQuery;
      } else if (state.pass == 2) {
        matchFunc = matchPassContains;
        hltFunc = highlightQuery;
      } else if (state.pass == 3) {
        matchFunc = matchPassRegexp;
        hltFunc = highlightRegexp;
      }

      for (; togo > 0 && i < l && state.limit > 0; i++, togo--) {
        if (info[i].n == state.n) continue;
        if (matchFunc(searchIndex[i], longSearchIndex[i], queries, regexps)) {
          info[i].n = state.n;
          result.push(hltFunc(info[i], queries, regexps, highlighters));
          state.limit--;
        }
      };
      if (searchIndex.length <= i) {
        state.pass++;
        i = state.from = 0;
      } else {
        state.from = i;
      }
    }
    return result;
  }

  function triggerResults(results, isLast) {
    this.handlers.forEach(function(fn) {
      fn.call(this, results, isLast)
    });
  }
}

