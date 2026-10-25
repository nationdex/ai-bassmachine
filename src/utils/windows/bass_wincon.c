/*
 * MCP Bass Machine - Windows Native Console & Key Input Engine
 * Ultra-low latency, non-blocking raw console I/O for Windows (x86_64 and i686).
 * Compatible with Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT on Windows.
 */

#include <windows.h>

typedef void (*push_int_fn)(void* L, long long n);
typedef void (*push_lstring_fn)(void* L, const char* s, size_t len);
typedef long long (*to_int_fn)(void* L, int idx, int* isnum);
typedef const char* (*to_lstring_fn)(void* L, int idx, size_t* len);

static push_int_fn p_pushinteger = NULL;
static push_lstring_fn p_pushlstring = NULL;
static to_int_fn p_tointeger = NULL;
static to_lstring_fn p_tolstring = NULL;
static HANDLE hConsoleIn = INVALID_HANDLE_VALUE;
static HANDLE hConsoleOut = INVALID_HANDLE_VALUE;
static DWORD orig_in_mode = 0;
static DWORD orig_out_mode = 0;
static int raw_enabled = 0;

static void init_handles(void) {
    if (hConsoleIn == INVALID_HANDLE_VALUE || hConsoleIn == NULL) {
        hConsoleIn = CreateFileA("CONIN$", GENERIC_READ | GENERIC_WRITE,
                                 FILE_SHARE_READ | FILE_SHARE_WRITE,
                                 NULL, OPEN_EXISTING, 0, NULL);
        if (hConsoleIn == INVALID_HANDLE_VALUE || hConsoleIn == NULL) {
            hConsoleIn = GetStdHandle(STD_INPUT_HANDLE);
        }
    }
    if (hConsoleOut == INVALID_HANDLE_VALUE || hConsoleOut == NULL) {
        hConsoleOut = CreateFileA("CONOUT$", GENERIC_READ | GENERIC_WRITE,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  NULL, OPEN_EXISTING, 0, NULL);
        if (hConsoleOut == INVALID_HANDLE_VALUE || hConsoleOut == NULL) {
            hConsoleOut = GetStdHandle(STD_OUTPUT_HANDLE);
        }
    }
}

static void init_lua_api(void) {
    if (p_pushinteger && p_pushlstring && p_tointeger) return;
    HMODULE hMods[] = {
        GetModuleHandle("lua54.dll"),
        GetModuleHandle("lua53.dll"),
        GetModuleHandle("lua52.dll"),
        GetModuleHandle("lua51.dll"),
        GetModuleHandle("luajit.dll"),
        GetModuleHandle("lua.dll"),
        GetModuleHandle(NULL)
    };
    for (size_t i = 0; i < sizeof(hMods)/sizeof(hMods[0]); i++) {
        if (!hMods[i]) continue;
        if (!p_pushinteger) {
            p_pushinteger = (push_int_fn)GetProcAddress(hMods[i], "lua_pushinteger");
        }
        if (!p_pushlstring) {
            p_pushlstring = (push_lstring_fn)GetProcAddress(hMods[i], "lua_pushlstring");
        }
        if (!p_tointeger) {
            p_tointeger = (to_int_fn)GetProcAddress(hMods[i], "lua_tointeger");
            if (!p_tointeger) {
                p_tointeger = (to_int_fn)GetProcAddress(hMods[i], "lua_tointegerx");
            }
        }
        if (!p_tolstring) {
            p_tolstring = (to_lstring_fn)GetProcAddress(hMods[i], "lua_tolstring");
        }
    }
}

__declspec(dllexport) int win_init(void* L) {
    init_handles();
    init_lua_api();
    if (!raw_enabled && hConsoleIn != INVALID_HANDLE_VALUE && hConsoleOut != INVALID_HANDLE_VALUE) {
        if (GetConsoleMode(hConsoleIn, &orig_in_mode) && GetConsoleMode(hConsoleOut, &orig_out_mode)) {
            raw_enabled = 1;
            // Output: ENABLE_PROCESSED_OUTPUT (1) | ENABLE_VIRTUAL_TERMINAL_PROCESSING (4)
            SetConsoleMode(hConsoleOut, orig_out_mode | 0x0005);
            // Input: disable ENABLE_LINE_INPUT (2) | ENABLE_ECHO_INPUT (4) | ENABLE_PROCESSED_INPUT (1)
            SetConsoleMode(hConsoleIn, (orig_in_mode & ~0x0007));
        }
    }
    if (p_pushinteger) {
        p_pushinteger(L, raw_enabled ? 1 : 0);
        return 1;
    }
    return 0;
}

__declspec(dllexport) int win_cleanup(void* L) {
    if (raw_enabled && hConsoleIn != INVALID_HANDLE_VALUE && hConsoleOut != INVALID_HANDLE_VALUE) {
        SetConsoleMode(hConsoleIn, orig_in_mode);
        SetConsoleMode(hConsoleOut, orig_out_mode);
        raw_enabled = 0;
    }
    return 0;
}

__declspec(dllexport) int win_sleep(void* L) {
    init_lua_api();
    long long ms = 15;
    if (p_tointeger) {
        long long val = p_tointeger(L, 1, NULL);
        if (val > 0) ms = val;
    }
    Sleep((DWORD)ms);
    return 0;
}

__declspec(dllexport) int win_mkdir_p(void* L) {
    init_lua_api();
    if (!p_tolstring) return 0;
    size_t len = 0;
    const char* path = p_tolstring(L, 1, &len);
    if (!path || len == 0 || len >= MAX_PATH) return 0;

    char tmp[MAX_PATH];
    strncpy(tmp, path, sizeof(tmp)-1);
    tmp[sizeof(tmp)-1] = 0;

    for (char* p = tmp; *p; p++) {
        if (*p == '/') *p = '\\';
    }

    for (char* p = tmp; *p; p++) {
        if (*p == '\\') {
            *p = 0;
            if (strlen(tmp) > 0 && tmp[strlen(tmp)-1] != ':') {
                CreateDirectoryA(tmp, NULL);
            }
            *p = '\\';
        }
    }
    int ok = CreateDirectoryA(tmp, NULL) || GetLastError() == ERROR_ALREADY_EXISTS;
    if (p_pushinteger) {
        p_pushinteger(L, ok ? 1 : 0);
        return 1;
    }
    return 0;
}

__declspec(dllexport) int win_get_window_size(void* L) {
    init_handles();
    init_lua_api();
    if (!p_pushinteger || hConsoleOut == INVALID_HANDLE_VALUE) return 0;
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (GetConsoleScreenBufferInfo(hConsoleOut, &csbi)) {
        int rows = csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
        int cols = csbi.srWindow.Right - csbi.srWindow.Left + 1;
        p_pushinteger(L, rows);
        p_pushinteger(L, cols);
        return 2;
    }
    return 0;
}

__declspec(dllexport) int win_poll_key(void* L) {
    init_handles();
    init_lua_api();
    if (!p_pushlstring || hConsoleIn == INVALID_HANDLE_VALUE) return 0;

    while (1) {
        DWORD numEvents = 0;
        if (!GetNumberOfConsoleInputEvents(hConsoleIn, &numEvents) || numEvents == 0) {
            return 0;
        }

        INPUT_RECORD rec;
        DWORD readCount = 0;
        if (!ReadConsoleInputA(hConsoleIn, &rec, 1, &readCount) || readCount == 0) {
            return 0;
        }

        // Only process KEY_EVENT; discard mouse, resize, focus, and menu events safely
        if (rec.EventType != KEY_EVENT) {
            continue;
        }

        // Discard key release (up) events immediately without blocking
        if (!rec.Event.KeyEvent.bKeyDown) {
            continue;
        }

        WORD vk = rec.Event.KeyEvent.wVirtualKeyCode;
        char ch = rec.Event.KeyEvent.uChar.AsciiChar;

        // Ignore standalone modifier key-downs (Shift, Ctrl, Alt, CapsLock, Windows key)
        if (vk == VK_SHIFT || vk == VK_CONTROL || vk == VK_MENU ||
            vk == VK_CAPITAL || vk == VK_LWIN || vk == VK_RWIN) {
            continue;
        }

        // 1. Navigation & Special Keys
        if (vk == VK_UP) { p_pushlstring(L, "up", 2); return 1; }
        if (vk == VK_DOWN) { p_pushlstring(L, "down", 4); return 1; }
        if (vk == VK_LEFT) { p_pushlstring(L, "left", 4); return 1; }
        if (vk == VK_RIGHT) { p_pushlstring(L, "right", 5); return 1; }
        if (vk == VK_HOME) { p_pushlstring(L, "home", 4); return 1; }
        if (vk == VK_END) { p_pushlstring(L, "end", 3); return 1; }
        if (vk == VK_PRIOR) { p_pushlstring(L, "page_up", 7); return 1; }
        if (vk == VK_NEXT) { p_pushlstring(L, "page_down", 9); return 1; }
        if (vk == VK_DELETE) { p_pushlstring(L, "delete", 6); return 1; }
        if (vk == VK_RETURN || ch == '\r' || ch == '\n') { p_pushlstring(L, "enter", 5); return 1; }
        if (vk == VK_BACK) { p_pushlstring(L, "backspace", 9); return 1; }
        if (vk == VK_TAB) { p_pushlstring(L, "tab", 3); return 1; }
        if (vk == VK_SPACE) { p_pushlstring(L, "space", 5); return 1; }

        // 2. Control Combinations
        if ((rec.Event.KeyEvent.dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED))) {
            if (ch == 3 || vk == 'C') { p_pushlstring(L, "ctrl_c", 6); return 1; }
            if (ch == 4 || vk == 'D') { p_pushlstring(L, "ctrl_d", 6); return 1; }
            if (ch == 17 || vk == 'Q') { p_pushlstring(L, "ctrl_q", 6); return 1; }
            if (ch == 18 || vk == 'R') { p_pushlstring(L, "ctrl_r", 6); return 1; }
            if (ch == 1 || vk == 'A') { p_pushlstring(L, "ctrl_a", 6); return 1; }
            if (ch == 5 || vk == 'E') { p_pushlstring(L, "ctrl_e", 6); return 1; }
        }

        // 3. Escape key
        if (vk == VK_ESCAPE || ch == 27) {
            p_pushlstring(L, "esc", 3);
            return 1;
        }

        // 4. Standard Printable Character
        if (ch >= 32 && ch < 127) {
            p_pushlstring(L, &ch, 1);
            return 1;
        }
    }
}
