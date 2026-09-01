// Rowing / BLE — placeholder for a later iteratie. No UI is wired up yet.
//
// Confirmed hardware (see project brief / nRF Connect):
//   Device       VirtuFit Water Resistance Aqua 100i
//   BLE name     FS-057453      MAC 77:C4:F3:B7:FB:6D
//   Services     0x1826 (Fitness Machine Service / FTMS)  — used
//                0xFFF0 (FitShow proprietary)             — ignored
//   Characteristics under 0x1826:
//     0x2ACC Fitness Machine Feature      READ
//     0x2AD9 Fitness Machine Control Point INDICATE/WRITE  (optional start/stop)
//     0x2AD1 Rower Data                   NOTIFY            (live fields)
//
// Standard FTMS parsing is enough — no custom byte decoding. The `flutter_ftms`
// package (^1.4.0, built on flutter_blue_plus) exposes this via:
//
//   await FTMS.scanForBluetoothDevices();
//   await FTMS.connectToFTMSDevice(device);
//   await FTMS.useDeviceDataCharacteristic(
//     device,
//     (DeviceData data) { /* Rower Data fields */ },
//     preferredDeviceDataType: DeviceDataType.rower,
//   );
//
// The Rower Data flags byte varies per notification (FTMS spec): not every field
// is present every time — the package handles the flag-driven offsets. Treat
// absolute distance/pace from this trainer as estimates (fine for trends).
//
// Android permissions (add to AndroidManifest before this lands):
//   BLUETOOTH_SCAN, BLUETOOTH_CONNECT (API 31+),
//   ACCESS_FINE_LOCATION (API < 31, for scanning).

/// Live snapshot from the rower, normalised from FTMS Rower Data.
class RowerSnapshot {
  const RowerSnapshot({
    this.strokeRate,
    this.strokeCount,
    this.distanceM,
    this.paceSec500m,
    this.powerW,
    this.energyKcal,
    this.heartRate,
    this.elapsedSeconds,
  });

  final double? strokeRate;
  final int? strokeCount;
  final double? distanceM;
  final double? paceSec500m;
  final double? powerW;
  final double? energyKcal;
  final int? heartRate;
  final int? elapsedSeconds;
}

/// To be implemented on top of `flutter_ftms` in the rowing iteratie.
abstract class FtmsRowerService {
  Stream<RowerSnapshot> get snapshots;
  Future<void> connect();
  Future<void> disconnect();
}
