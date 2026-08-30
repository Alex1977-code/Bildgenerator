import '../roblox_install.dart';

Future<RobloxInstall> findRobloxStudio() async => const RobloxInstall(
      found: false,
      note: 'In der Web-Version lässt sich das nicht prüfen – dafür '
          'die Windows- oder Android-App verwenden.',
    );

Future<bool> openRobloxFolder(String path) async => false;
