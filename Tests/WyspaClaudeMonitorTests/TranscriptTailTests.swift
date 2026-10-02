import Foundation
import Testing
@testable import WyspaClaudeMonitor

@Suite("Wykrywanie przerwania w zapisie sesji")
struct TranscriptTailTests {
    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
    }
    private func user(_ text: String) -> String {
        line(["type": "user", "message": ["role": "user", "content": [["type": "text", "text": text]]]])
    }
    private var assistant: String { line(["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": "ok"]]]]) }
    private var attachment: String { line(["type": "attachment", "attachment": ["type": "async_hook_response"]]) }

    @Test("Ostatnia wiadomość to przerwanie (także przy odrzuceniu narzędzia i po wpisach pomocniczych)")
    func interrupted() {
        #expect(TranscriptTail.endsWithInterrupt(Data((assistant + user("[Request interrupted by user]")).utf8)))
        #expect(TranscriptTail.endsWithInterrupt(Data((assistant + user("[Request interrupted by user for tool use]") + attachment).utf8)))
    }

    @Test("Zwykła wiadomość, odpowiedź Claude albo niedopisany wiersz to nie przerwanie")
    func notInterrupted() {
        #expect(!TranscriptTail.endsWithInterrupt(Data((user("[Request interrupted by user]") + assistant).utf8)))
        #expect(!TranscriptTail.endsWithInterrupt(Data(user("napisz test").utf8)))
        #expect(!TranscriptTail.endsWithInterrupt(Data((assistant + "{\"type\":\"user\",\"mess").utf8)))
        #expect(!TranscriptTail.endsWithInterrupt(Data()))
    }

    @Test("Akceptowane tylko bezwzględne ścieżki .jsonl bez ..")
    func paths() {
        #expect(TranscriptTail.isAcceptablePath("/Users/x/.claude/projects/p/s.jsonl"))
        #expect(!TranscriptTail.isAcceptablePath("relative/s.jsonl"))
        #expect(!TranscriptTail.isAcceptablePath("/etc/passwd"))
        #expect(!TranscriptTail.isAcceptablePath("/Users/x/../../etc/s.jsonl"))
    }

    @Test("Prawdziwy plik: obserwator widzi dopisane przerwanie")
    @MainActor
    func watcher() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-\(UUID().uuidString).jsonl")
        try Data(user("start").utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = AsyncStream<Bool>.makeStream()
        let watcher = TranscriptWatcher(path: url.path) { result.continuation.yield($0) }
        defer { watcher.cancel() }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(user("[Request interrupted by user]").utf8))
        try handle.close()
        var iterator = result.stream.makeAsyncIterator()
        #expect(await iterator.next() == true)
    }
}
