#ifndef RUNNER_WINDOW_STATE_H_
#define RUNNER_WINDOW_STATE_H_

#include <windows.h>

// Merkt sich Groesse, Lage und Maximierung des Fensters ueber das
// Programmende hinaus. Abgelegt wird das in der Registry unter
// HKEY_CURRENT_USER\Software\3DGenerator\Fenster - ein Ort, den
// Windows selbst fuer solche Kleinigkeiten vorsieht und der ohne
// Schreibrechte im Programmordner auskommt.

// Uebernimmt die zuletzt gemerkte Lage. Gibt es keine, oder liegt sie
// ausserhalb aller angeschlossenen Bildschirme (Monitor abgezogen),
// bleibt das Fenster, wo es ist.
bool ApplyWindowState(HWND window);

// Schreibt die aktuelle Lage weg. Bis [ApplyWindowState] gelaufen ist,
// tut das nichts: Beim Erzeugen des Fensters schickt Windows bereits
// eine Groessenmeldung mit den Vorgabewerten, und die wuerde sonst den
// gemerkten Stand ueberschreiben, bevor er gelesen wird. Ist das Fenster minimiert, wird die
// Lage gespeichert, die es beim Wiederherstellen einnimmt - sonst
// startete die App beim naechsten Mal als schmaler Streifen.
void SaveWindowState(HWND window);

#endif  // RUNNER_WINDOW_STATE_H_
