/// Die Ports der beiden mitgelieferten Server.
///
/// Sie stehen getrennt, weil zwei Prozesse denselben Port nicht
/// belegen können: Trägt man beide Server auf dieselbe Adresse ein,
/// bekommt einer von beiden keine Verbindung – und der Fehler sieht
/// aus wie eine kaputte Installation.
const int threeDDefaultPort = 8765;
const int imageDefaultPort = 8766;
