// Finds the text worth reading on a web page: the person's selection if
// they made one, or else the page's article, with its title.
//
// Safari runs this on the page being shared (NSExtensionJavaScriptPreprocessingFile)
// and hands the result to the extension. The extension runs the same file in
// its own web view for links shared from other apps. The keys of the result
// match SharedItem.PageKey.
var StrobeArticle = (function () {
    "use strict";

    // Elements whose text is read as a paragraph.
    var BLOCKS = "p, h1, h2, h3, h4, h5, h6, li, blockquote, pre, dd, dt";
    // Blocks that are read even while hidden: many sites collapse the rest
    // of an article behind a Read More button. Hidden lists are menus and
    // category links.
    var PROSE = "p, h1, h2, h3, h4, h5, h6, blockquote";
    // Page furniture: never part of the article. Tables are skipped too, as
    // they are in EPUBs; read a word at a time, they're noise.
    var SKIPPED = "nav, aside, footer, form, figure, table, button, dialog, noscript, script, style, template, " +
        "[role=navigation], [role=complementary], [role=contentinfo], [aria-hidden=true], [hidden]";
    var JUNK_NAME = /(^|[\s_-])(ad|ads|advert|banner|breadcrumbs?|caption|carousel|comments?|cookie|footer|gallery|masthead|menu|newsletter|paywall|promo|related|share|sharing|sidebar|signup|slideshow|social|sponsored|subscribe|toolbar)([\s_-]|$)/i;
    // Between a headline and the site name in a page title.
    var TITLE_SEPARATORS = [" | ", " - ", " \u2013 ", " \u2014 ", " \u00b7 ", " :: "];
    // Footnote markers such as [1], [a], and [citation needed].
    var FOOTNOTE = /\[(?:\d+|[a-z]|citation needed|note \d+)\]/gi;
    // Plenty for any article, and small enough for an extension's memory.
    var MAX_LENGTH = 2000000;

    function collapse(text) {
        return (text || "").replace(/\s+/g, " ").trim();
    }

    function wordCount(text) {
        var trimmed = collapse(text);
        return trimmed ? trimmed.split(" ").length : 0;
    }

    function meta(selector) {
        var element = document.querySelector(selector);
        return element ? collapse(element.getAttribute("content")) : "";
    }

    // The headline, without the site name many pages append to it.
    function title(root) {
        var heading = (root && root.querySelector("h1")) || document.querySelector("h1");
        var headline = heading ? collapse(heading.innerText) : "";
        var text = meta('meta[property="og:title"]') || meta('meta[name="twitter:title"]') ||
            collapse(document.title) || headline;
        var siteName = meta('meta[property="og:site_name"]');
        for (var i = 0; i < TITLE_SEPARATORS.length; i++) {
            var separator = TITLE_SEPARATORS[i];
            if (headline && text.indexOf(headline + separator) === 0) return headline;
            if (siteName && text.length > (separator + siteName).length &&
                text.slice(-(separator + siteName).length) === separator + siteName) {
                return text.slice(0, -(separator + siteName).length);
            }
        }
        return text;
    }

    function isSkipped(element, root) {
        for (var node = element; node && node !== root; node = node.parentElement) {
            if (node.matches(SKIPPED)) return true;
            var name = (node.id || "") + " " + (typeof node.className === "string" ? node.className : "");
            if (JUNK_NAME.test(name)) return true;
        }
        return false;
    }

    // Text in <p> elements under `element`, the measure of an article.
    function paragraphLength(element) {
        var total = 0;
        var paragraphs = element.querySelectorAll("p");
        for (var i = 0; i < paragraphs.length; i++) {
            total += collapse(paragraphs[i].textContent).length;
        }
        return total;
    }

    // The element holding the article: a marked-up article if there is one
    // with real text, or else the element whose paragraphs hold the most text.
    function articleRoot() {
        var best = null;
        var bestLength = 0;
        var marked = document.querySelectorAll('article, [itemprop="articleBody"], main, [role="main"]');
        for (var i = 0; i < marked.length; i++) {
            var length = paragraphLength(marked[i]);
            if (length > bestLength) {
                best = marked[i];
                bestLength = length;
            }
        }
        if (best && bestLength >= 500) return best;

        var scores = new Map();
        var paragraphs = document.body ? document.body.querySelectorAll("p") : [];
        for (var j = 0; j < paragraphs.length; j++) {
            var paragraph = paragraphs[j];
            var textLength = collapse(paragraph.textContent).length;
            if (textLength < 80) continue;
            var parent = paragraph.parentElement;
            if (!parent) continue;
            scores.set(parent, (scores.get(parent) || 0) + textLength);
            if (parent.parentElement) {
                scores.set(parent.parentElement, (scores.get(parent.parentElement) || 0) + textLength / 2);
            }
        }
        var top = null;
        var topScore = 0;
        scores.forEach(function (score, element) {
            if (score > topScore) {
                top = element;
                topScore = score;
            }
        });
        return top || best || document.body;
    }

    function articleText(root) {
        if (!root) return "";
        var paragraphs = [];
        var last = null;
        var blocks = root.querySelectorAll(BLOCKS);
        for (var i = 0; i < blocks.length; i++) {
            var block = blocks[i];
            // A block inside another block is read as part of the outer one.
            if (block.parentElement && block.parentElement.closest(BLOCKS) &&
                root.contains(block.parentElement.closest(BLOCKS))) continue;
            if (isSkipped(block, root)) continue;
            if (block.getClientRects().length === 0 && !block.matches(PROSE)) continue;
            var text = block.matches("pre") ? block.innerText.trim() : collapse(block.innerText.replace(FOOTNOTE, ""));
            if (!text || text === last) continue;
            paragraphs.push(text);
            last = text;
        }
        var joined = paragraphs.join("\n\n");
        // Articles laid out without paragraph elements: take the whole root.
        var whole = root.innerText || "";
        if (wordCount(joined) < wordCount(whole) * 0.3) joined = whole.trim();
        return joined.slice(0, MAX_LENGTH);
    }

    function extract() {
        var selection = window.getSelection ? String(window.getSelection()).trim() : "";
        if (selection) {
            return { title: title(null), text: selection.slice(0, MAX_LENGTH), url: document.URL, isSelection: true };
        }
        var root = articleRoot();
        return { title: title(root), text: articleText(root), url: document.URL, isSelection: false };
    }

    return { extract: extract };
})();

var ExtensionPreprocessingJS = {
    run: function (parameters) {
        var result;
        try {
            result = StrobeArticle.extract();
        } catch (error) {
            result = { title: document.title, text: document.body ? document.body.innerText : "", url: document.URL, isSelection: false };
        }
        parameters.completionFunction(result);
    },
    finalize: function () {}
};
