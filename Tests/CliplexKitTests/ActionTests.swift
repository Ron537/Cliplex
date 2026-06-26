import Foundation
import Testing
@testable import CliplexKit

@Suite struct ActionLogicTests {

    // MARK: - Clipboard template expansion

    @Test func expandsClipboardPlaceholderUnencoded() {
        let out = ActionLogic.expand("open {clipboard} now", clipboard: "a b", urlEncoded: false)
        #expect(out == "open a b now")
    }

    @Test func expandsClipboardPlaceholderURLEncoded() {
        let out = ActionLogic.expand("q={clipboard}", clipboard: "a b&c", urlEncoded: true)
        #expect(out == "q=a%20b%26c")
    }

    @Test func expandLeavesTemplateUntouchedWithoutPlaceholder() {
        let out = ActionLogic.expand("https://example.com", clipboard: "ignored", urlEncoded: true)
        #expect(out == "https://example.com")
    }

    @Test func resolvedURLBuildsValidSearchURL() {
        let url = ActionLogic.resolvedURL(
            template: "https://github.com/search?q={clipboard}", clipboard: "swift testing")
        #expect(url?.absoluteString == "https://github.com/search?q=swift%20testing")
    }

    @Test func resolvedURLRejectsEmpty() {
        #expect(ActionLogic.resolvedURL(template: "", clipboard: "x") == nil)
        #expect(ActionLogic.resolvedURL(template: "   ", clipboard: "x") == nil)
    }

    @Test func resolvedURLRequiresScheme() {
        // A bare host (no scheme) isn't openable — reject it so the caller can
        // report the error instead of silently failing.
        #expect(ActionLogic.resolvedURL(template: "github.com", clipboard: "x") == nil)
        #expect(ActionLogic.resolvedURL(template: "not a url", clipboard: "x") == nil)
        #expect(ActionLogic.resolvedURL(template: "https://github.com", clipboard: "x")?.scheme == "https")
    }

    // MARK: - Transforms

    @Test func caseTransforms() {
        #expect(ActionLogic.apply(.uppercase, to: "aBc") == "ABC")
        #expect(ActionLogic.apply(.lowercase, to: "aBc") == "abc")
        #expect(ActionLogic.apply(.titlecase, to: "hello world") == "Hello World")
        #expect(ActionLogic.apply(.trim, to: "  hi \n") == "hi")
    }

    @Test func base64RoundTrips() {
        let encoded = ActionLogic.apply(.base64Encode, to: "Hello, 世界")
        #expect(encoded == "SGVsbG8sIOS4lueVjA==")
        #expect(ActionLogic.apply(.base64Decode, to: encoded!) == "Hello, 世界")
    }

    @Test func base64DecodeRejectsGarbage() {
        #expect(ActionLogic.apply(.base64Decode, to: "not valid base64!") == nil)
    }

    @Test func urlEncodeDecodeRoundTrips() {
        let encoded = ActionLogic.apply(.urlEncode, to: "a b/c?d=e")
        #expect(encoded == "a%20b%2Fc%3Fd%3De")
        #expect(ActionLogic.apply(.urlDecode, to: encoded!) == "a b/c?d=e")
    }

    @Test func jsonPrettyAndMinify() {
        let pretty = ActionLogic.apply(.jsonPretty, to: "{\"b\":1,\"a\":2}")
        #expect(pretty == "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        let minified = ActionLogic.apply(.jsonMinify, to: "{ \"a\" : 2 , \"b\" : 1 }")
        #expect(minified == "{\"a\":2,\"b\":1}")
    }

    @Test func jsonRejectsMalformed() {
        #expect(ActionLogic.apply(.jsonPretty, to: "{not json}") == nil)
    }

    @Test func sha256Hashes() {
        #expect(ActionLogic.apply(.sha256, to: "abc")
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

@Suite struct ActionStoreTests {
    private func makeStore() throws -> ClipStore { try ClipStore() }

    @Test func actionFolderAndActionCRUD() throws {
        let store = try makeStore()
        let folder = try store.addActionFolder(name: "Dev")
        #expect(try store.listActionFolders().map(\.name) == ["Dev"])

        let action = try store.addAction(
            folderID: folder.id, title: "My Repo", type: .openURL,
            value: "https://github.com/me/repo", transform: nil)
        #expect(action.type == .openURL)
        #expect(try store.listActions(folderID: folder.id).map(\.title) == ["My Repo"])

        try store.updateAction(
            id: action.id, title: "Repo", type: .openURL,
            value: "https://github.com/me/repo2", transform: nil)
        #expect(try store.action(id: action.id).value == "https://github.com/me/repo2")

        let transformAction = try store.addAction(
            folderID: folder.id, title: "Upper", type: .transform, value: "", transform: .uppercase)
        #expect(try store.action(id: transformAction.id).transform == .uppercase)

        try store.deleteAction(id: action.id)
        #expect(try store.listActions(folderID: folder.id).map(\.id) == [transformAction.id])
    }

    @Test func deletingFolderCascadesActions() throws {
        let store = try makeStore()
        let folder = try store.addActionFolder(name: "Temp")
        _ = try store.addAction(folderID: folder.id, title: "A", type: .openURL, value: "x", transform: nil)
        try store.deleteActionFolder(id: folder.id)
        #expect(try store.listActions(folderID: nil).isEmpty)
    }

    @Test func searchActionsMatchesTitleAndValue() throws {
        let store = try makeStore()
        _ = try store.addAction(folderID: nil, title: "GitHub", type: .openURL,
                                value: "https://github.com", transform: nil)
        _ = try store.addAction(folderID: nil, title: "Search", type: .openURL,
                                value: "https://google.com/search", transform: nil)
        #expect(try store.searchActions("github", limit: 50).map(\.title) == ["GitHub"])
        #expect(try store.searchActions("google", limit: 50).map(\.title) == ["Search"])
    }

    @Test func reorderActionsPersistsOrder() throws {
        let store = try makeStore()
        let a = try store.addAction(folderID: nil, title: "A", type: .openURL, value: "1", transform: nil)
        let b = try store.addAction(folderID: nil, title: "B", type: .openURL, value: "2", transform: nil)
        try store.setActionOrder([b.id, a.id])
        #expect(try store.listActions(folderID: nil).map(\.title) == ["B", "A"])
    }
}
