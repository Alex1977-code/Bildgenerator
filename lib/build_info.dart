/// Build-Kennung aus der CI (`--dart-define=BUILD_INFO=…`): Commit und
/// Build-Datum. So lässt sich jederzeit prüfen, welcher Stand gerade
/// läuft – wichtig bei der Web-Version, deren Service-Worker-Cache
/// nach einem Update gern noch einmal die alte Version ausliefert
/// (dann hilft erneutes Neuladen). Lokale Entwicklungs-Builds zeigen
/// „Entwicklung“.
library;

const String buildInfo =
    String.fromEnvironment('BUILD_INFO', defaultValue: 'Entwicklung');
