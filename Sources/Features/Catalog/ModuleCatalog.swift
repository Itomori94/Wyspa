import WyspaBluetooth
import WyspaCalendar
import WyspaClaudeMonitor
import WyspaClipboard
import WyspaCore
import WyspaHUD
import WyspaMedia
import WyspaMirror
import WyspaNotes
import WyspaPower
import WyspaReminders
import WyspaShelf
import WyspaShortcuts
import WyspaTimer

/// Jedyne miejsce rejestracji modułów. Nowy moduł = nowy target w Sources/Features i jedna linia tutaj.
/// Kolejność = kolejność zakładek w wyspie i na liście w ustawieniach.
public enum ModuleCatalog {
    @MainActor
    public static let all: [any IslandModule.Type] = [
        MediaModule.self,
        ShelfModule.self,
        CalendarModule.self,
        RemindersModule.self,
        TimerModule.self,
        NotesModule.self,
        ClipboardModule.self,
        ShortcutsModule.self,
        MirrorModule.self,
        ClaudeMonitorModule.self,
        HUDModule.self,
        PowerModule.self,
        BluetoothModule.self,
    ]
}
