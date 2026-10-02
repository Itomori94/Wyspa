import Foundation

/// Reaguje na dopisanie do zapisu sesji Claude Code i sprawdza, czy ostatnia wiadomość to przerwanie.
@MainActor
final class TranscriptWatcher {
    let path: String
    private let source: DispatchSourceFileSystemObject?
    private let handle: FileHandle?

    init(path: String, onChange: @escaping @MainActor (_ interrupted: Bool) -> Void) {
        self.path = path
        // Ścieżka przychodzi z hooka: otwieramy tylko zwykły plik należący do nas, bez dowiązań i bez blokowania
        // (np. kolejka FIFO nazwana „x.jsonl” zawiesiłaby główny wątek na zwykłym `open`).
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        var info = stat()
        guard descriptor >= 0, fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else {
            if descriptor >= 0 { close(descriptor) }
            self.source = nil
            self.handle = nil
            return
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak source] in
            // Plik usunięty albo przeniesiony: dalsze obserwowanie nie ma sensu, deskryptor się zamyka.
            if let source, !source.data.intersection([.delete, .rename]).isEmpty {
                source.cancel()
                return
            }
            MainActor.assumeIsolated {
                onChange(TranscriptTail.readTail(of: handle).map(TranscriptTail.endsWithInterrupt) ?? false)
            }
        }
        // Jeden deskryptor do zdarzeń i odczytu; zamykany tylko tutaj.
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        self.handle = handle
    }

    func cancel() {
        source?.cancel()
    }

    isolated deinit {
        source?.cancel()
    }
}
