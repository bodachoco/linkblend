import Foundation

// MARK: - net-merge status file

struct NIC: Decodable {
    var Name: String
    var IP: String?
    var IP6: String?
    var State: String?
    var State6: String?
    var Weight: Double?
    var Active: Int?
    var Total: Int?
    var Failed: Int?
    var BytesIn: Double?
    var BytesOut: Double?
    var RateIn: Double?
    var RateOut: Double?
    var Peak: Double?
}

struct NMStatus: Decodable {
    var PID: Int?
    var Mode: String?
    var Updated: String?
    var NICs: [NIC]
}
