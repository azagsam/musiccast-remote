import Foundation

struct Station: Identifiable, Hashable {
    /// Position in the receiver's result list. Only valid until the list is next navigated.
    let index: Int
    let name: String

    var id: Int { index }
}

struct ListInfo: Decodable {
    struct Item: Decodable {
        let text: String
        let attribute: Int

        var isSelectable: Bool { attribute & 0x2 != 0 }
        var isPlayable: Bool { attribute & 0x4 != 0 }
        var isSearchable: Bool { attribute & 0x8 != 0 }
    }

    let menu_layer: Int
    let max_line: Int
    let list_info: [Item]
}

/// Drives the receiver's on-device net radio menu: Radio > Search > results.
/// The menu is shared state, so other controllers can move it between calls.
struct RadioBrowser {
    private static let pageSize = 8
    private static let maxResults = 48

    let client: Client

    func search(_ query: String) async throws -> [Station] {
        try await returnToRoot()

        let root = try await page(at: 0)
        guard let radio = root.list_info.firstIndex(where: { $0.text == "Radio" && $0.isSelectable }) else {
            throw AppError("This receiver has no Radio menu")
        }
        try await client.send("netusb/setListControl?list_id=main&type=select&index=\(radio)&zone=main")
        let menu = try await waitForLayer(1)

        guard let search = menu.list_info.firstIndex(where: \.isSearchable) else {
            throw AppError("This receiver has no radio search")
        }
        try await client.post("netusb/setSearchString", body: SearchRequest(string: query, index: search))
        _ = try await waitForLayer(2)

        return try await results()
    }

    func play(_ station: Station) async throws {
        // The list may have moved since the search, and an index would then play something else.
        let start = station.index / Self.pageSize * Self.pageSize
        let items = try await page(at: start).list_info
        let offset = station.index - start
        guard offset < items.count, items[offset].text == station.name else {
            throw AppError("The results have changed. Search again.")
        }
        try await client.send("netusb/setListControl?list_id=main&type=play&index=\(station.index)&zone=main")
    }

    private func results() async throws -> [Station] {
        var stations: [Station] = []
        var index = 0
        while index < Self.maxResults {
            let list = try await page(at: index)
            for (offset, item) in list.list_info.enumerated() where item.isPlayable {
                stations.append(Station(index: index + offset, name: item.text))
            }
            index += Self.pageSize
            if index >= list.max_line { break }
        }
        return stations
    }

    private func page(at index: Int) async throws -> ListInfo {
        try await client.get("netusb/getListInfo?input=net_radio&index=\(index)&size=\(Self.pageSize)&lang=en")
    }

    private func returnToRoot() async throws {
        var layer = try await page(at: 0).menu_layer
        var attempts = 0
        while layer > 0 && attempts < 10 {
            try await client.send("netusb/setListControl?list_id=main&type=return&zone=main")
            try await Task.sleep(nanoseconds: 200_000_000)
            layer = try await page(at: 0).menu_layer
            attempts += 1
        }
        guard layer == 0 else { throw AppError("Couldn't reach the top of the radio menu") }
    }

    private func waitForLayer(_ layer: Int) async throws -> ListInfo {
        for _ in 0..<20 {
            let list = try await page(at: 0)
            if list.menu_layer == layer { return list }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw AppError("The receiver took too long to respond")
    }
}

private struct SearchRequest: Encodable {
    let string: String
    let index: Int
}
