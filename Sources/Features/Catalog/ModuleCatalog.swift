import WyspaBluetooth
import WyspaCalendar
import WyspaClaudeMonitor
import WyspaClipboard
import WyspaDownloads
import WyspaCore
import WyspaHUD
import WyspaMedia
import WyspaMicrophone
import WyspaMirror
import WyspaNotes
import WyspaNotifications
import WyspaPower
import WyspaQuickActions
import WyspaReminders
import WyspaScripts
import WyspaShelf
import WyspaShortcuts
import WyspaTimer
import WyspaWeather

/// Jedyne miejsce rejestracji modułów. Nowy moduł = nowy target w Sources/Features i jedna linia tutaj.
/// Kolejność = kolejność zakładek w wyspie i na liście w ustawieniach.
public enum ModuleCatalog {
    @MainActor
    public static let all: [any IslandModule.Type] = [
        MediaModule.self,
        ShelfModule.self,
        DownloadsModule.self,
        CalendarModule.self,
        WeatherModule.self,
        RemindersModule.self,
        TimerModule.self,
        NotesModule.self,
        ClipboardModule.self,
        ShortcutsModule.self,
        ScriptsModule.self,
        QuickActionsModule.self,
        MirrorModule.self,
        MicrophoneModule.self,
        ClaudeMonitorModule.self,
        NotificationsModule.self,
        HUDModule.self,
        PowerModule.self,
        BluetoothModule.self,
    ]
}
