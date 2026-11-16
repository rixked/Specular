import 'dart:io' show Platform;

/// `linux`, `windows` or `android`, as stored in device files.
String currentPlatform() => Platform.operatingSystem;

/// A reasonable default device name until the user picks one: the host
/// name on desktop ("arch-pc"), the platform name on mobile.
String defaultDeviceName() {
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iPhone';
  final host = Platform.localHostname.trim();
  if (host.isNotEmpty && host != 'localhost') return host;
  return Platform.isWindows ? 'Windows PC' : 'Linux PC';
}
