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

  function summaryToggle() {
    $(".summary_toggle").click(function (e) {
      e.preventDefault();
      localStorage.summaryCollapsed = $(this).text();
      $(".summary_toggle").each(function () {
        $(this).text($(this).text() == "collapse" ? "expand" : "collapse");
        var next = $(this).parent().parent().nextAll("ul.summary").first();
        if (next.hasClass("compact")) {
          next.toggle();
          next.nextAll("ul.summary").first().toggle();
        } else if (next.hasClass("summary")) {
          var list = $('<ul class="summary compact" />');
          list.html(next.html());
          list.find(".summary_desc, .note").remove();
          list.find("a").each(function () {
            $(this).html($(this).find("strong").html());
            $(this).parent().html($(this)[0].outerHTML);
          });
          next.before(list);
          next.toggle();
        }
      });
      return false;
    });
    if (localStorage.summaryCollapsed == "collapse") {
      $(".summary_toggle").first().click();
    } else {
      localStorage.summaryCollapsed = "expand";
    }
  }

  function constantSummaryToggle() {
    $(".constants_summary_toggle").click(function (e) {
      e.preventDefault();
      localStorage.summaryCollapsed = $(this).text();
      $(".constants_summary_toggle").each(function () {
        $(this).text($(this).text() == "collapse" ? "expand" : "collapse");
        var next = $(this).parent().parent().nextAll("dl.constants").first();
        if (next.hasClass("compact")) {
          next.toggle();
          next.nextAll("dl.constants").first().toggle();
        } else if (next.hasClass("constants")) {
          var list = $('<dl class="constants compact" />');
          list.html(next.html());
          list.find("dt").each(function () {
            $(this).addClass("summary_signature");
            $(this).text($(this).text().split("=")[0]);
            if ($(this).has(".deprecated").length) {
              $(this).addClass("deprecated");
            }
          });
          // Add the value of the constant as "Tooltip" to the summary object
          list.find("pre.code").each(function () {
            var dt_element = $(this).parent().prev();
            var tooltip = $(this).text();
            if (dt_element.hasClass("deprecated")) {
              tooltip = "Deprecated. " + tooltip;
            }
            dt_element.attr("title", tooltip);
          });
          list.find(".docstring, .tags, dd").remove();
          next.before(list);
          next.toggle();
        }
      });
      return false;
    });
    if (localStorage.summaryCollapsed == "collapse") {
      $(".constants_summary_toggle").first().click();
    } else {
      localStorage.summaryCollapsed = "expand";
    }
  }

  function generateTOC() {
    if ($("#filecontents").length === 0) return;
    var _toc = $('<ol class="top"></ol>');
    var show = false;
    var toc = _toc;
    var counter = 0;
    var tags = ["h2", "h3", "h4", "h5", "h6"];
    var i;
    var curli;
    if ($("#filecontents h1").length > 1) tags.unshift("h1");
    for (i = 0; i < tags.length; i++) {
      tags[i] = "#filecontents " + tags[i];
    }
    var lastTag = parseInt(tags[0][1], 10);
    $(tags.join(", ")).each(function () {
      if ($(this).parents(".method_details .docstring").length != 0) return;
      if (this.id == "filecontents") return;
      show = true;
      var thisTag = parseInt(this.tagName[1], 10);
      if (this.id.length === 0) {
        var proposedId = $(this).attr("toc-id");
        if (typeof proposedId != "undefined") this.id = proposedId;
        else {
          var proposedId = $(this)
            .text()
            .replace(/[^a-z0-9-]/gi, "_");
          if ($("#" + proposedId).length > 0) {
            proposedId += counter;
            counter++;
          }
          this.id = proposedId;
        }
      }
      if (thisTag > lastTag) {
        for (i = 0; i < thisTag - lastTag; i++) {
          if (typeof curli == "undefined") {
            curli = $("<li/>");
            toc.append(curli);
          }
          toc = $("<ol/>");
          curli.append(toc);
          curli = undefined;
        }
      }
      if (thisTag < lastTag) {
        for (i = 0; i < lastTag - thisTag; i++) {
          toc = toc.parent();
          toc = toc.parent();
        }
      }
      var title = $(this).attr("toc-title");
      if (typeof title == "undefined") title = $(this).text();
      curli = $('<li><a href="#' + this.id + '">' + title + "</a></li>");
      toc.append(curli);
      lastTag = thisTag;
    });
    if (!show) return;
    html =
      '<div id="toc"><p class="title hide_toc"><a href="#"><strong>Table of Contents</strong></a></p></div>';
    $("#content").prepend(html);
    $("#toc").append(_toc);
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

window.addEventListener(
  "message",
  async (e) => {
    if (e.data.action === "navigate") {
      const classListLink = document.getElementById("class_list_link");
      const classListBaseUrl = new URL(
        classListLink.getAttribute("href"),
        window.location.href
      );
      const resolvedUrl = new URL(e.data.url, classListBaseUrl);

      const response = await fetch(resolvedUrl);
      const text = await response.text();
      const parser = new DOMParser();
      const doc = parser.parseFromString(text, "text/html");

      const classListLinkClasses =
        document.getElementById("class_list_link").classList;

      const content = doc.querySelector("#main").innerHTML;
      document.querySelector("#main").innerHTML = content;
      document.title = doc.head.querySelector("title").innerText;
      document.head.querySelectorAll("script").forEach((script) => {
        if (
          !script.type ||
          (script.type.includes("text/javascript") && !script.src)
        ) {
          script.remove();
        }
      });

      doc.head.querySelectorAll("script").forEach((script) => {
        if (
          !script.type ||
          (script.type.includes("text/javascript") && !script.src)
        ) {
          const newScript = document.createElement("script");
          newScript.type = "text/javascript";
          newScript.textContent = script.textContent;
          document.head.appendChild(newScript);
        }
      });

      window.__app();

      document.getElementById("class_list_link").classList =
        classListLinkClasses;

      const url = resolvedUrl;
      const hash = decodeURIComponent(url.hash ?? "");
      if (hash) {
        document.getElementById(hash.substring(1)).scrollIntoView();
      }
      history.pushState({}, document.title, resolvedUrl);
    }
  },
  false
);
