import CoreBluetooth
import Foundation

/// Native CoreBluetooth illuminate - no WKWebView/JS bridge needed here
/// since there's no web view at all. Same collect-then-pick approach as
/// the Mac app: the board doesn't reliably advertise a name containing
/// "Tension" (a real unit showed up as "NH00012AA6"), so this gathers
/// nearby devices for a few seconds and lets the UI show a picker rather
/// than guessing by name prefix.
@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    @Published var status: String = ""
    @Published var candidates: [CBPeripheral] = []
    @Published var isPickingDevice = false
    @Published var lastError: String?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var pendingChunks: [[UInt8]] = []
    private var discovered: [UUID: CBPeripheral] = [:]
    private var collectionTimer: Timer?

    private nonisolated static let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    private nonisolated static let characteristicUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    private static let collectionWindow: TimeInterval = 4

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func illuminate(frames: String, placementPositions: [Int: Int], ledColors: [Int: String]) {
        let packet = BluetoothPacket.build(frames: frames, placementPositions: placementPositions, ledColors: ledColors)
        pendingChunks = BluetoothPacket.chunks(packet)
        lastError = nil

        if let peripheral, peripheral.state == .connected, let characteristic {
            writeNextChunk(to: peripheral, characteristic: characteristic)
            return
        }

        guard centralManager.state == .poweredOn else {
            lastError = "Bluetooth is off, or this app hasn't been granted access yet (Settings > Bluetooth)."
            return
        }

        startScan()
    }

    func choosePeripheral(_ chosen: CBPeripheral) {
        isPickingDevice = false
        peripheral = chosen
        chosen.delegate = self
        status = "Connecting…"
        centralManager.connect(chosen, options: nil)
    }

    func cancelPicker() {
        isPickingDevice = false
        status = ""
    }

    private func startScan() {
        status = "Looking for nearby Bluetooth devices…"
        discovered.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        collectionTimer?.invalidate()
        collectionTimer = Timer.scheduledTimer(withTimeInterval: Self.collectionWindow, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finishCollecting() }
        }
    }

    private func finishCollecting() {
        centralManager.stopScan()
        let found = discovered.values
            .filter { $0.name != nil }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }

        guard !found.isEmpty else {
            lastError = "No nearby Bluetooth devices found. Make sure the board is powered on and in range."
            return
        }
        candidates = found
        isPickingDevice = true
        status = ""
    }

    private func writeNextChunk(to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard !pendingChunks.isEmpty else {
            status = "Lit up!"
            return
        }
        let chunk = pendingChunks.removeFirst()
        let data = Data(chunk)
        if characteristic.properties.contains(.write) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        } else {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            writeNextChunk(to: peripheral, characteristic: characteristic)
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        Task { @MainActor in self.discovered[peripheral.identifier] = peripheral }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.lastError = "Failed to connect: \(error?.localizedDescription ?? "unknown error")" }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if !self.pendingChunks.isEmpty {
                self.lastError = "Lost connection to the board mid-write."
            }
            self.peripheral = nil
            self.characteristic = nil
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        guard let service = services.first(where: { $0.uuid == Self.serviceUUID }) else {
            Task { @MainActor in
                self.lastError = "That device didn't expose the expected Bluetooth service - probably not the board."
            }
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
            Task { @MainActor in self.lastError = "That device didn't expose the expected Bluetooth characteristic." }
            return
        }
        Task { @MainActor in
            self.characteristic = characteristic
            self.writeNextChunk(to: peripheral, characteristic: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = "Write failed: \(error.localizedDescription)"
                return
            }
            self.writeNextChunk(to: peripheral, characteristic: characteristic)
        }
    }
}
