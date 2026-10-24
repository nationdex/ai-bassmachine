/*
 * MCP Bass Machine - Windows Native Console & Key Input Engine
 * Ultra-low latency, non-blocking raw console I/O for Windows (x86_64 and i686).
 * Compatible with Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT on Windows.
 */

#include <windows.h>

typedef void (*push_int_fn)(void* L, long long n);
typedef void (*push_lstring_fn)(void* L, const char* s, size_t len);
typedef long long (*to_int_fn)(void* L, int idx);

static push_int_fn p_pushinteger = NULL;
static push_lstring_fn p_pushlstring = NULL;
static to_int_fn p_tointeger = NULL;
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
        GetModuleHandle(NULL),
        GetModuleHandle("lua54.dll"),
        GetModuleHandle("lua53.dll"),
        GetModuleHandle("lua52.dll"),
        GetModuleHandle("lua51.dll"),
        GetModuleHandle("lua.dll"),
        GetModuleHandle("luajit.dll")
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
        long long val = p_tointeger(L, 1);
        if (val > 0) ms = val;
    }
    Sleep((DWORD)ms);
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

    DWORD numEvents = 0;
    if (!GetNumberOfConsoleInputEvents(hConsoleIn, &numEvents) || numEvents == 0) {
        return 0;
    }

    INPUT_RECORD records[32];
    DWORD readCount = 0;
    if (!PeekConsoleInputA(hConsoleIn, records, sizeof(records)/sizeof(records[0]), &readCount) || readCount == 0) {
        return 0;
    }

    for (DWORD i = 0; i < readCount; i++) {
        if (records[i].EventType == KEY_EVENT) {
            INPUT_RECORD discard[32];
            DWORD discarded = 0;
            ReadConsoleInputA(hConsoleIn, discard, i + 1, &discarded);

            if (!records[i].Event.KeyEvent.bKeyDown) {
                continue;
            }

            WORD vk = records[i].Event.KeyEvent.wVirtualKeyCode;
            char ch = records[i].Event.KeyEvent.uChar.AsciiChar;

            // 1. Navigation Keys
            if (vk == VK_UP) { p_pushlstring(L, "up", 2); return 1; }
            if (vk == VK_DOWN) { p_pushlstring(L, "down", 4); return 1; }
            if (vk == VK_LEFT) { p_pushlstring(L, "left", 4); return 1; }
            if (vk == VK_RIGHT) { p_pushlstring(L, "right", 5); return 1; }
            if (vk == VK_HOME) { p_pushlstring(L, "home", 4); return 1; }
            if (vk == VK_END) { p_pushlstring(L, "end", 3); return 1; }
            if (vk == VK_PRIOR) { p_pushlstring(L, "page_up", 7); return 1; }
            if (vk == VK_NEXT) { p_pushlstring(L, "page_down", 9); return 1; }
            if (vk == VK_DELETE) { p_pushlstring(L, "delete", 6); return 1; }
            if (vk == VK_RETURN) { p_pushlstring(L, "enter", 5); return 1; }
            if (vk == VK_BACK) { p_pushlstring(L, "backspace", 9); return 1; }
            if (vk == VK_TAB) { p_pushlstring(L, "tab", 3); return 1; }
            if (vk == VK_SPACE) { p_pushlstring(L, "space", 5); return 1; }

            // 2. Control Combinations
            if ((records[i].Event.KeyEvent.dwControlKeyState & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED))) {
                if (ch == 3 || vk == 'C') { p_pushlstring(L, "ctrl_c", 6); return 1; }
                if (ch == 4 || vk == 'D') { p_pushlstring(L, "ctrl_d", 6); return 1; }
                if (ch == 17 || vk == 'Q') { p_pushlstring(L, "ctrl_q", 6); return 1; }
                if (ch == 18 || vk == 'R') { p_pushlstring(L, "ctrl_r", 6); return 1; }
            }

            // 3. Escape key or VT sequences (peeking ahead, skipping key-up events)
            if (vk == VK_ESCAPE || ch == 27) {
                INPUT_RECORD nextRecs[16];
                DWORD nextCount = 0;
                char seq[8] = {0};
                int seqLen = 0;
                if (PeekConsoleInputA(hConsoleIn, nextRecs, sizeof(nextRecs)/sizeof(nextRecs[0]), &nextCount) && nextCount > 0) {
                    DWORD discardTotal = 0;
                    for (DWORD j = 0; j < nextCount && seqLen < 4; j++) {
                        if (nextRecs[j].EventType == KEY_EVENT) {
                            discardTotal = j + 1;
                            if (nextRecs[j].Event.KeyEvent.bKeyDown) {
                                seq[seqLen++] = nextRecs[j].Event.KeyEvent.uChar.AsciiChar;
                            }
                        }
                    }
                    if (seqLen >= 2 && (seq[0] == '[' || seq[0] == 'O')) {
                        ReadConsoleInputA(hConsoleIn, discard, discardTotal, &discarded);
                        if (seq[1] == 'A') { p_pushlstring(L, "up", 2); return 1; }
                        if (seq[1] == 'B') { p_pushlstring(L, "down", 4); return 1; }
                        if (seq[1] == 'C') { p_pushlstring(L, "right", 5); return 1; }
                        if (seq[1] == 'D') { p_pushlstring(L, "left", 4); return 1; }
                        if (seq[1] == 'H') { p_pushlstring(L, "home", 4); return 1; }
                        if (seq[1] == 'F') { p_pushlstring(L, "end", 3); return 1; }
                    }
                }
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

    // Flush any pending non-key events (mouse move, window size, focus)
    INPUT_RECORD flushRecs[32];
    DWORD flushed = 0;
    ReadConsoleInputA(hConsoleIn, flushRecs, readCount, &flushed);
    return 0;
}
