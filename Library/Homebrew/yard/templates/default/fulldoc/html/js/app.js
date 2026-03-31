window.__app = function () {
  var localStorage = {},
    sessionStorage = {};
  try {
    localStorage = window.localStorage;
  } catch (e) {}
  try {
    sessionStorage = window.sessionStorage;
  } catch (e) {}

  function createSourceLinks() {
    $(".method_details_list .source_code").before(
      "<span class='showSource'>[<a href='#' class='toggleSource'>View source</a>]</span>"
    );
    $(".toggleSource").toggle(
      function () {
        $(this).parent().nextAll(".source_code").slideDown(100);
        $(this).text("Hide source");
      },
      function () {
        $(this).parent().nextAll(".source_code").slideUp(100);
        $(this).text("View source");
      }
    );
  }

  function createDefineLinks() {
    var tHeight = 0;
    $(".defines").after(" <a href='#' class='toggleDefines'>more...</a>");
    $(".toggleDefines").toggle(
      function () {
        tHeight = $(this).parent().prev().height();
        $(this).prev().css("display", "inline");
        $(this).parent().prev().height($(this).parent().height());
        $(this).text("(less)");
      },
      function () {
        $(this).prev().hide();
        $(this).parent().prev().height(tHeight);
        $(this).text("more...");
      }
    );
  }

  function createFullTreeLinks() {
    var tHeight = 0;
    $(".inheritanceTree").toggle(
      function () {
        tHeight = $(this).parent().prev().height();
        $(this).parent().toggleClass("showAll");
        $(this).text("(hide)");
        $(this).parent().prev().height($(this).parent().height());
      },
      function () {
        $(this).parent().toggleClass("showAll");
        $(this).parent().prev().height(tHeight);
        $(this).text("show all");
      }
    );
  }

  function searchFrameButtons() {
    $(".full_list_link").click(function () {
      toggleSearchFrame(this, $(this).attr("href"));
      return false;
    });
    window.addEventListener("message", function (e) {
      if (e.data === "navEscape") {
        $("#nav").slideUp(100);
        $("#search a").removeClass("active inactive");
        $(window).focus();
      }
    });

    $(window).resize(function () {
      if ($("#search:visible").length === 0) {
        $("#nav").removeAttr("style");
        $("#search a").removeClass("active inactive");
        $(window).focus();
      }
    });
  }

  function toggleSearchFrame(id, link) {
    var frame = $("#nav");
    $("#search a").removeClass("active").addClass("inactive");
    if (frame.attr("src") === link && frame.css("display") !== "none") {
      frame.slideUp(100);
      $("#search a").removeClass("active inactive");
    } else {
      $(id).addClass("active").removeClass("inactive");
      if (frame.attr("src") !== link) frame.attr("src", link);
      frame.slideDown(100);
    }
  }

  function linkSummaries() {
    $(".summary_signature").click(function () {
      document.location = $(this).find("a").attr("href");
    });
  }

  function initializeSummaryToggle(
    toggleSelector,
    summarySelector,
    expandedClass,
    buildCompactList
  ) {
    $(toggleSelector).click(function (e) {
      e.preventDefault();
      localStorage.summaryCollapsed = $(this).text();
      $(toggleSelector).each(function () {
        $(this).text($(this).text() == "collapse" ? "expand" : "collapse");
        var next = $(this).parent().parent().nextAll(summarySelector).first();
        if (next.hasClass("compact")) {
          next.toggle();
          next.nextAll(summarySelector).first().toggle();
        } else if (next.hasClass(expandedClass)) {
          var list = buildCompactList(next);
          next.before(list);
          next.toggle();
        }
      });
      return false;
    });

    if (localStorage.summaryCollapsed == "collapse") {
      $(toggleSelector).first().click();
    } else {
      localStorage.summaryCollapsed = "expand";
    }
  }

  function buildCompactSummaryList(next) {
    var list = $('<ul class="summary compact" />');
    list.html(next.html());
    list.find(".summary_desc, .note").remove();
    list.find("a").each(function () {
      $(this).html($(this).find("strong").html());
      $(this).parent().html($(this)[0].outerHTML);
    });
    return list;
  }

  function buildCompactConstantsList(next) {
    var list = $('<dl class="constants compact" />');
    list.html(next.html());
    list.find("dt").each(function () {
      $(this).addClass("summary_signature");
      $(this).text($(this).text().split("=")[0]);
      if ($(this).has(".deprecated").length) {
        $(this).addClass("deprecated");
      }
    });
    list.find("pre.code").each(function () {
      var dt_element = $(this).parent().prev();
      var tooltip = $(this).text();
      if (dt_element.hasClass("deprecated")) {
        tooltip = "Deprecated. " + tooltip;
      }
      dt_element.attr("title", tooltip);
    });
    list.find(".docstring, .tags, dd").remove();
    return list;
  }

  function summaryToggle() {
    initializeSummaryToggle(
      ".summary_toggle",
      "ul.summary",
      "summary",
      buildCompactSummaryList
    );
  }

  function constantSummaryToggle() {
    initializeSummaryToggle(
      ".constants_summary_toggle",
      "dl.constants",
      "constants",
      buildCompactConstantsList
    );
  }

  function buildTOCTags() {
    var tags = ["h2", "h3", "h4", "h5", "h6"];
    if ($("#filecontents h1").length > 1) tags.unshift("h1");
    return tags;
  }

  function buildTOCSelectors(tags) {
    var selectors = [];
    for (var i = 0; i < tags.length; i++) {
      selectors.push("#filecontents " + tags[i]);
    }
    return selectors;
  }

  function shouldSkipTOCElement(element) {
    if ($(element).parents(".method_details .docstring").length != 0) return true;
    if (element.id == "filecontents") return true;
    return false;
  }

  function ensureTOCElementId(element, counter) {
    if (element.id.length !== 0) return;
    var proposedId = $(element).attr("toc-id");
    if (typeof proposedId != "undefined") {
      element.id = proposedId;
      return;
    }

    proposedId = $(element)
      .text()
      .replace(/[^a-z0-9-]/gi, "_");
    if ($("#" + proposedId).length > 0) {
      proposedId += counter.value;
      counter.value++;
    }
    element.id = proposedId;
  }

  function normalizeTOCLevel(state, thisTag) {
    var i;
    if (thisTag > state.lastTag) {
      for (i = 0; i < thisTag - state.lastTag; i++) {
        if (typeof state.curli == "undefined") {
          state.curli = $("<li/>");
          state.toc.append(state.curli);
        }
        state.toc = $("<ol/>");
        state.curli.append(state.toc);
        state.curli = undefined;
      }
    }

    if (thisTag < state.lastTag) {
      for (i = 0; i < state.lastTag - thisTag; i++) {
        state.toc = state.toc.parent();
        state.toc = state.toc.parent();
      }
    }
  }

  function appendTOCEntry(state, element) {
    var thisTag = parseInt(element.tagName[1], 10);
    normalizeTOCLevel(state, thisTag);
    var title = $(element).attr("toc-title");
    if (typeof title == "undefined") title = $(element).text();
    state.curli = $('<li><a href="#' + element.id + '">' + title + "</a></li>");
    state.toc.append(state.curli);
    state.lastTag = thisTag;
  }

  function renderTOC(tocList) {
    var html =
      '<div id="toc"><p class="title hide_toc"><a href="#"><strong>Table of Contents</strong></a></p></div>';
    $("#content").prepend(html);
    $("#toc").append(tocList);
    $("#toc .hide_toc").toggle(
      function () {
        $("#toc .top").slideUp("fast");
        $("#toc").toggleClass("hidden");
        $("#toc .title small").toggle();
      },
      function () {
        $("#toc .top").slideDown("fast");
        $("#toc").toggleClass("hidden");
        $("#toc .title small").toggle();
      }
    );
  }

  function generateTOC() {
    if ($("#filecontents").length === 0) return;
    var tags = buildTOCTags();
    var selectors = buildTOCSelectors(tags);
    var tocList = $('<ol class="top"></ol>');
    var state = {
      toc: tocList,
      curli: undefined,
      lastTag: parseInt(tags[0][1], 10),
    };
    var counter = { value: 0 };
    var show = false;

    $(selectors.join(", ")).each(function () {
      if (shouldSkipTOCElement(this)) return;
      show = true;
      ensureTOCElementId(this, counter);
      appendTOCEntry(state, this);
    });
    if (!show) return;
    renderTOC(tocList);
  }

  function navResizer() {
    const resizer = document.getElementById("resizer");
    resizer.addEventListener(
      "pointerdown",
      function (e) {
        resizer.setPointerCapture(e.pointerId);
        e.preventDefault();
        e.stopPropagation();
      },
      false
    );
    resizer.addEventListener(
      "pointerup",
      function (e) {
        resizer.releasePointerCapture(e.pointerId);
        e.preventDefault();
        e.stopPropagation();
      },
      false
    );
    resizer.addEventListener(
      "pointermove",
      function (e) {
        if ((e.buttons & 1) === 0) {
          return;
        }

        sessionStorage.navWidth = e.pageX.toString();
        $(".nav_wrap").css("width", Math.max(200, e.pageX));
        e.preventDefault();
        e.stopPropagation();
      },
      false
    );

    if (sessionStorage.navWidth) {
      $(".nav_wrap").css(
        "width",
        Math.max(200, parseInt(sessionStorage.navWidth, 10))
      );
    }
  }

  function navExpander() {
    if (typeof pathId === "undefined") return;
    var done = false,
      timer = setTimeout(postMessage, 500);
    function postMessage() {
      if (done) return;
      clearTimeout(timer);
      var opts = { action: "expand", path: pathId };
      document.getElementById("nav").contentWindow.postMessage(opts, "*");
      done = true;
    }
  }

  function mainFocus() {
    var hash = window.location.hash;
    if (hash !== "" && $(hash)[0]) {
      $(hash)[0].scrollIntoView();
    }

    setTimeout(function () {
      $("#main").focus();
    }, 10);
  }

  function navigationChange() {
    // This works around the broken anchor navigation with the YARD template.
    window.onpopstate = function () {
      var hash = window.location.hash;
      if (hash !== "" && $(hash)[0]) {
        $(hash)[0].scrollIntoView();
      }
    };
  }

  $(document).ready(function () {
    navResizer();
    navExpander();
    createSourceLinks();
    createDefineLinks();
    createFullTreeLinks();
    searchFrameButtons();
    linkSummaries();
    summaryToggle();
    constantSummaryToggle();
    generateTOC();
    mainFocus();
    navigationChange();
  });
};
window.__app();

function isInlineJavaScript(script) {
  return (
    !script.type ||
    (script.type.includes("text/javascript") && !script.src)
  );
}

function replaceMainContent(doc) {
  const content = doc.querySelector("#main").innerHTML;
  document.querySelector("#main").innerHTML = content;
  document.title = doc.head.querySelector("title").innerText;
}

function refreshHeadScripts(doc) {
  document.head.querySelectorAll("script").forEach((script) => {
    if (isInlineJavaScript(script)) {
      script.remove();
    }
  });

  doc.head.querySelectorAll("script").forEach((script) => {
    if (isInlineJavaScript(script)) {
      const newScript = document.createElement("script");
      newScript.type = "text/javascript";
      newScript.textContent = script.textContent;
      document.head.appendChild(newScript);
    }
  });
}

function restoreClassList(classListLink) {
  document.getElementById("class_list_link").classList = classListLink;
}

function scrollToDecodedHash(rawUrl) {
  const url = new URL(rawUrl, "https://localhost");
  const hash = decodeURIComponent(url.hash ?? "");
  if (hash) {
    document.getElementById(hash.substring(1)).scrollIntoView();
  }
}

async function handleNavigate(url) {
  const response = await fetch(url);
  const text = await response.text();
  const parser = new DOMParser();
  const doc = parser.parseFromString(text, "text/html");
  const classListLink = document.getElementById("class_list_link").classList;

  replaceMainContent(doc);
  refreshHeadScripts(doc);
  window.__app();
  restoreClassList(classListLink);
  scrollToDecodedHash(url);
  history.pushState({}, document.title, url);
}

window.addEventListener(
  "message",
  async (e) => {
    if (e.data.action === "navigate") {
      await handleNavigate(e.data.url);
    }
  },
  false
);
