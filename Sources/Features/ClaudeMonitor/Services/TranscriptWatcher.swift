import Foundation

/// Reaguje na dopisanie do zapisu sesji Claude Code i sprawdza, czy ostatnia wiadomość to przerwanie.
@MainActor
final class TranscriptWatcher {
    let path: String
    private let source: DispatchSourceFileSystemObject?
    private let handle: FileHandle?

    init(path: String, onChange: @escaping @MainActor (_ interrupted: Bool) -> Void) {
        self.path = path
        let descriptor = open(path, O_EVTONLY)
        let handle = FileHandle(forReadingAtPath: path)
        guard descriptor >= 0, let handle else {
            if descriptor >= 0 { close(descriptor) }
            self.source = nil
            self.handle = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend],
                                                               queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                onChange(TranscriptTail.readTail(of: handle).map(TranscriptTail.endsWithInterrupt) ?? false)
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        self.handle = handle
    }

    func cancel() {
        source?.cancel()
        try? handle?.close()
    }
}
