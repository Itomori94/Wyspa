import Testing
@testable import WyspaMedia

@Suite("Głośniki AirPlay w Muzyce")
struct AirPlayTests {
    let output = "MacBook Pro\u{1F}computer\u{1F}false\u{1F}true\u{1E}Salon\u{1F}Apple TV\u{1F}true\u{1F}true\u{1E}Kuchnia\u{1F}HomePod\u{1F}false\u{1F}false\u{1E}"

    @Test("Odczyt listy z wyjścia skryptu")
    func parse() {
        let devices = AirPlayScript.parse(output)
        #expect(devices.map(\.name) == ["MacBook Pro", "Salon", "Kuchnia"])
        #expect(devices[1].isSelected && devices[1].symbol == "appletv.fill")
        #expect(!devices[2].isAvailable && devices[0].symbol == "laptopcomputer")
        #expect(AirPlayScript.parse("").isEmpty && AirPlayScript.parse("zepsute").isEmpty)
    }

    @Test("Przełączanie: dodaje, usuwa, ale nie zostawia pustego wyboru")
    func toggle() {
        let devices = AirPlayScript.parse(output)
        #expect(AirPlayScript.toggling("MacBook Pro", in: devices) == ["Salon", "MacBook Pro"])
        #expect(AirPlayScript.toggling("Salon", in: devices) == ["Salon"])
    }

    @Test("Nazwy w skrypcie są bezpiecznie cytowane")
    func escaping() {
        let script = AirPlayScript.selectScript(["Pokój \"Toma\"", "A\\B"])
        #expect(script == #"tell application "Music" to set current AirPlay devices to {AirPlay device "Pokój \"Toma\"", AirPlay device "A\\B"}"#)
    }
}
