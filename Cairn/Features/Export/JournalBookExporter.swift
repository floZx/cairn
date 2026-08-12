import AppKit
import WebKit

/// The book's HTML, turned into a paginated PDF.
///
/// WebKit does the one genuinely hard part: a day runs to ten lines or three
/// pages depending on how much was done, and the stylesheet says where a break
/// may fall. Neither `ImageRenderer` — one view per page, the splitting left to
/// us — nor Core Graphics knows how to do that.
@MainActor
enum JournalBookExporter {
    /// A4 at 96 dpi. The page size that matters is the stylesheet's `@page`;
    /// this only decides how wide the layout is measured before printing.
    private static let pageSize = NSRect(x: 0, y: 0, width: 794, height: 1123)

    static func pdf(from html: String) async throws -> Data {
        let webView = WKWebView(frame: pageSize, configuration: WKWebViewConfiguration())
        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter
        webView.loadHTMLString(html, baseURL: nil)
        try await waiter.waitForLoad()
        // Held to here on purpose: a navigation delegate is a weak reference,
        // and a waiter released at the end of the line above would take the
        // continuation with it.
        withExtendedLifetime(waiter) {}
        return try await webView.pdf()
    }

    /// A navigation delegate that hands its continuation back when the page is
    /// laid out — there is no synchronous way to know a `WKWebView` is done.
    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var finished = false
        private var failure: Error?

        func waitForLoad() async throws {
            if finished { return }
            if let failure { throw failure }
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished = true
            continuation?.resume()
            continuation = nil
        }

        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            fail(error)
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            fail(error)
        }

        private func fail(_ error: Error) {
            failure = error
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
