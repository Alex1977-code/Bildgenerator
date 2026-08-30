#include "window_state.h"

namespace {

constexpr wchar_t kKey[] = L"Software\\3DGenerator\\Fenster";

// Kleinste sinnvolle Fenstergroesse. Kleiner gespeicherte Werte sind
// fast immer ein Unfall (Fenster beim Beenden gerade minimiert oder
// von einem Skript zusammengezogen) und werden verworfen.
constexpr LONG kMinWidth = 640;
constexpr LONG kMinHeight = 480;

// Erst nach dem Wiederherstellen darf gespeichert werden, siehe
// window_state.h.
bool g_ready = false;

bool ReadValue(HKEY key, const wchar_t* name, DWORD* value) {
  DWORD type = 0;
  DWORD size = sizeof(DWORD);
  if (RegQueryValueExW(key, name, nullptr, &type,
                       reinterpret_cast<BYTE*>(value), &size) != ERROR_SUCCESS) {
    return false;
  }
  return type == REG_DWORD;
}

void WriteValue(HKEY key, const wchar_t* name, DWORD value) {
  RegSetValueExW(key, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value),
                 sizeof(value));
}

}  // namespace

bool ApplyWindowState(HWND window) {
  g_ready = true;
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kKey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  DWORD left = 0, top = 0, width = 0, height = 0, maximized = 0;
  const bool complete = ReadValue(key, L"Links", &left) &&
                        ReadValue(key, L"Oben", &top) &&
                        ReadValue(key, L"Breite", &width) &&
                        ReadValue(key, L"Hoehe", &height);
  ReadValue(key, L"Maximiert", &maximized);
  RegCloseKey(key);
  if (!complete) {
    return false;
  }

  RECT stored = {static_cast<LONG>(static_cast<int>(left)),
                 static_cast<LONG>(static_cast<int>(top)),
                 static_cast<LONG>(static_cast<int>(left)) +
                     static_cast<LONG>(width),
                 static_cast<LONG>(static_cast<int>(top)) +
                     static_cast<LONG>(height)};
  if (stored.right - stored.left < kMinWidth ||
      stored.bottom - stored.top < kMinHeight) {
    return false;
  }

  // Liegt das Fenster noch auf einem Bildschirm? Nach dem Abziehen
  // eines zweiten Monitors zeigen die alten Werte sonst ins Leere und
  // die App startet unsichtbar.
  RECT desktop = {GetSystemMetrics(SM_XVIRTUALSCREEN),
                  GetSystemMetrics(SM_YVIRTUALSCREEN), 0, 0};
  desktop.right = desktop.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
  desktop.bottom = desktop.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
  RECT overlap;
  if (!IntersectRect(&overlap, &stored, &desktop) ||
      (overlap.right - overlap.left) < 200 ||
      (overlap.bottom - overlap.top) < 100) {
    return false;
  }

  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement)) {
    return false;
  }
  placement.rcNormalPosition = stored;
  placement.showCmd = maximized ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
  return SetWindowPlacement(window, &placement) != FALSE;
}

void SaveWindowState(HWND window) {
  if (!window || !g_ready) {
    return;
  }
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement)) {
    return;
  }
  // rcNormalPosition ist die Lage im nicht maximierten Zustand - genau
  // die, die beim naechsten Start gebraucht wird.
  const RECT& rect = placement.rcNormalPosition;
  const LONG width = rect.right - rect.left;
  const LONG height = rect.bottom - rect.top;
  if (width < kMinWidth || height < kMinHeight) {
    return;
  }

  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kKey, 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS) {
    return;
  }
  WriteValue(key, L"Links", static_cast<DWORD>(rect.left));
  WriteValue(key, L"Oben", static_cast<DWORD>(rect.top));
  WriteValue(key, L"Breite", static_cast<DWORD>(width));
  WriteValue(key, L"Hoehe", static_cast<DWORD>(height));
  WriteValue(key, L"Maximiert",
             placement.showCmd == SW_SHOWMAXIMIZED ? 1u : 0u);
  RegCloseKey(key);
}
