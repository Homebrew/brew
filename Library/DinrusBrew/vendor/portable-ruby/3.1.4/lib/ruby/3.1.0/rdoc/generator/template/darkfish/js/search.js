Search = function(data, input, result) {
  this.data = data;
  this.input = input;
  this.result = result;

  this.current = null;
  this.view = this.result.parentNode;
  this.searcher = new Searcher(data.index);
  this.init();
}

Search.prototype = Object.assign({}, Navigation, new function() {
  var suid = 1;

  this.init = function() {
    var _this = this;
    var observer = function(e) {
      switch(e.keyCode) {
        case 38: // Event.KEY_UP
        case 40: // Event.KEY_DOWN
          return;
      }
      _this.search(_this.input.value);
    };
    this.input.addEventListener('keyup', observer);
    this.input.addEventListener('click', observer); // mac's clear field

    this.searcher.ready(function(results, isLast) {
      _this.addResults(results, isLast);
    })

    this.initNavigation();
    this.setNavigationActive(false);
  }

  this.search = function(value, selectFirstMatch) {
    value = value.trim().toLowerCase();
    if (value) {
      this.setNavigationActive(true);
    } else {
      this.setNavigationActive(false);
    }

    if (value == '') {
      this.lastQuery = value;
      this.result.innerHTML = '';
      this.result.setAttribute('aria-expanded', 'false');
      this.setNavigationActive(false);
    } else if (value != this.lastQuery) {
      this.lastQuery = value;
      this.result.setAttribute('aria-busy',     'true');
      this.result.setAttribute('aria-expanded', 'true');
      this.firstRun = true;
      this.searcher.find(value);
    }
  }

  this.addResults = function(results, isLast) {
    var target = this.result;
    if (this.firstRun && (results.length > 0 || isLast)) {
      this.current = null;
      this.result.innerHTML = '';
    }

    for (var i=0, l = results.length; i < l; i++) {
      var item = this.renderItem.call(this, results[i]);
      item.setAttribute('id', 'search-result-' + target.childElementCount);
      target.appendChild(item);
    };

    if (this.firstRun && results.length > 0) {
      this.firstRun = false;
      this.current = target.firstChild;
      this.current.classList.add('search-selected');
    }
    //TODO: ECMAScript
    //if (jQuery.browser.msie) this.$element[0].className += '';

    if (isLast) this.result.setAttribute('aria-busy', 'false');
  }

  this.move = function(isDown) {
    if (!this.current) return;
    var next = isDown ? this.current.nextElementSibling : this.current.previousElementSibling;
    if (next) {
      this.current.classList.remove('search-selected');
      next.classList.add('search-selected');
      this.input.setAttribute('aria-activedescendant', next.getAttribute('id'));
      this.scrollIntoView(next, this.view);
      this.current = next;
      this.input.value = next.firstChild.firstChild.text;
      this.input.select();
    }
    return true;
  }

  this.hlt = function(html) {
    return this.escapeHTML(html).
      replace(/\u0001/g, '<em>').
      replace(/\u0002/g, '</em>');
  }

  this.escapeHTML = function(html) {
    return html.replace(/[&<>]/g, function(c) {
      return '&#' + c.charCodeAt(0) + ';';
    });
  }

});

