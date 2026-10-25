/*
 * MCP Bass Machine - Windows Native Console & Key Input Engine
 * Ultra-low latency, non-blocking raw console I/O for Windows (x86_64 and i686).
 * Compatible with Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT on Windows.
 */

#include <windows.h>
#include <string.h>

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


/*
 * Bidirectional child process support (Lua's io.popen is one-way on Windows, which made MCP
 * stdio servers impossible to drive). Each child gets stdin/stdout anonymous pipes, stderr goes
 * to a log file, and the whole process tree is bound to a job object so win_kill reaps npx/node
 * grandchildren too.
 */
#define MAX_PROCS 8

typedef struct {
    int used;
    HANDLE hProcess;
    HANDLE hJob;
    HANDLE hStdinWrite;
    HANDLE hStdoutRead;
    DWORD pid;
} ProcSlot;

static ProcSlot procs[MAX_PROCS];

static void close_slot(ProcSlot* ps) {
    if (ps->hStdinWrite) CloseHandle(ps->hStdinWrite);
    if (ps->hStdoutRead) CloseHandle(ps->hStdoutRead);
    if (ps->hJob) {
        TerminateJobObject(ps->hJob, 1);
        CloseHandle(ps->hJob);
    } else if (ps->hProcess) {
        TerminateProcess(ps->hProcess, 1);
    }
    if (ps->hProcess) CloseHandle(ps->hProcess);
    memset(ps, 0, sizeof(*ps));
}

static ProcSlot* get_slot(void* L, int idx) {
    int isnum = 0;
    long long id = p_tointeger ? p_tointeger(L, idx, &isnum) : 0;
    if (id < 1 || id > MAX_PROCS || !procs[id - 1].used) return NULL;
    return &procs[id - 1];
}

/* win_spawn(cmdline, stderr_log_path) -> id, pid  (nothing on failure) */
__declspec(dllexport) int win_spawn(void* L) {
    init_lua_api();
    if (!p_tolstring || !p_pushinteger) return 0;
    size_t clen = 0, plen = 0;
    const char* cmd = p_tolstring(L, 1, &clen);
    const char* errpath = p_tolstring(L, 2, &plen);
    if (!cmd || clen == 0 || clen > 32000) return 0;

    int slot = -1;
    for (int i = 0; i < MAX_PROCS; i++) {
        if (!procs[i].used) { slot = i; break; }
    }
    if (slot < 0) return 0;

    SECURITY_ATTRIBUTES sa;
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;

    HANDLE inRead = NULL, inWrite = NULL, outRead = NULL, outWrite = NULL, errH = NULL;
    if (!CreatePipe(&inRead, &inWrite, &sa, 0)) return 0;
    if (!CreatePipe(&outRead, &outWrite, &sa, 0)) {
        CloseHandle(inRead); CloseHandle(inWrite);
        return 0;
    }
    /* Parent's ends must not leak into the child */
    SetHandleInformation(inWrite, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(outRead, HANDLE_FLAG_INHERIT, 0);

    if (errpath && plen > 0) {
        errH = CreateFileA(errpath, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    }
    if (!errH || errH == INVALID_HANDLE_VALUE) {
        errH = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
    }

    STARTUPINFOA si;
    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = inRead;
    si.hStdOutput = outWrite;
    si.hStdError = errH;

    char* mutable_cmd = (char*)HeapAlloc(GetProcessHeap(), 0, clen + 1);
    if (!mutable_cmd) {
        CloseHandle(inRead); CloseHandle(inWrite); CloseHandle(outRead); CloseHandle(outWrite);
        if (errH != INVALID_HANDLE_VALUE) CloseHandle(errH);
        return 0;
    }
    memcpy(mutable_cmd, cmd, clen);
    mutable_cmd[clen] = 0;

    PROCESS_INFORMATION pi;
    memset(&pi, 0, sizeof(pi));
    BOOL ok = CreateProcessA(NULL, mutable_cmd, NULL, NULL, TRUE,
                             CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_BREAKAWAY_FROM_JOB,
                             NULL, NULL, &si, &pi);
    if (!ok) {
        /* Parent may itself be in a job that forbids breakaway; retry without the flag */
        ok = CreateProcessA(NULL, mutable_cmd, NULL, NULL, TRUE,
                            CREATE_NO_WINDOW | CREATE_SUSPENDED, NULL, NULL, &si, &pi);
    }
    HeapFree(GetProcessHeap(), 0, mutable_cmd);

    /* Child owns its ends now */
    CloseHandle(inRead);
    CloseHandle(outWrite);
    if (errH != INVALID_HANDLE_VALUE) CloseHandle(errH);

    if (!ok) {
        CloseHandle(inWrite);
        CloseHandle(outRead);
        return 0;
    }

    HANDLE job = CreateJobObjectA(NULL, NULL);
    if (job) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION jeli;
        memset(&jeli, 0, sizeof(jeli));
        jeli.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, &jeli, sizeof(jeli));
        if (!AssignProcessToJobObject(job, pi.hProcess)) {
            CloseHandle(job);
            job = NULL;
        }
    }
    ResumeThread(pi.hThread);
    CloseHandle(pi.hThread);

    procs[slot].used = 1;
    procs[slot].hProcess = pi.hProcess;
    procs[slot].hJob = job;
    procs[slot].hStdinWrite = inWrite;
    procs[slot].hStdoutRead = outRead;
    procs[slot].pid = pi.dwProcessId;

    p_pushinteger(L, slot + 1);
    p_pushinteger(L, (long long)pi.dwProcessId);
    return 2;
}

/* win_write(id, data) -> bytes written (nothing on failure) */
__declspec(dllexport) int win_write(void* L) {
    init_lua_api();
    ProcSlot* ps = get_slot(L, 1);
    if (!ps || !p_tolstring || !p_pushinteger) return 0;
    size_t len = 0;
    const char* data = p_tolstring(L, 2, &len);
    if (!data) return 0;
    size_t total = 0;
    while (total < len) {
        DWORD wrote = 0;
        if (!WriteFile(ps->hStdinWrite, data + total, (DWORD)(len - total), &wrote, NULL) || wrote == 0) {
            break;
        }
        total += wrote;
    }
    p_pushinteger(L, (long long)total);
    return 1;
}

/*
 * win_read(id, max_bytes, timeout_ms) -> string
 *   "" when nothing arrived before the timeout, nothing (nil) once the child closed stdout
 *   and every buffered byte has been consumed.
 */
__declspec(dllexport) int win_read(void* L) {
    init_lua_api();
    ProcSlot* ps = get_slot(L, 1);
    if (!ps || !p_pushlstring || !p_tointeger) return 0;
    long long maxb = p_tointeger(L, 2, NULL);
    long long timeout = p_tointeger(L, 3, NULL);
    if (maxb < 1) maxb = 4096;
    if (maxb > 65536) maxb = 65536;
    if (timeout < 0) timeout = 0;

    DWORD start = GetTickCount();
    for (;;) {
        DWORD avail = 0;
        if (!PeekNamedPipe(ps->hStdoutRead, NULL, 0, NULL, &avail, NULL)) {
            return 0; /* broken pipe: child exited and pipe is drained */
        }
        if (avail > 0) {
            char buf[65536];
            DWORD want = avail < (DWORD)maxb ? avail : (DWORD)maxb;
            DWORD got = 0;
            if (!ReadFile(ps->hStdoutRead, buf, want, &got, NULL) || got == 0) return 0;
            p_pushlstring(L, buf, got);
            return 1;
        }
        if ((long long)(GetTickCount() - start) >= timeout) {
            p_pushlstring(L, "", 0);
            return 1;
        }
        Sleep(5);
    }
}

/* win_alive(id) -> 1 running / 0 exited */
__declspec(dllexport) int win_alive(void* L) {
    init_lua_api();
    ProcSlot* ps = get_slot(L, 1);
    if (!ps || !p_pushinteger) return 0;
    p_pushinteger(L, WaitForSingleObject(ps->hProcess, 0) == WAIT_TIMEOUT ? 1 : 0);
    return 1;
}

/* win_kill(id): terminate the whole process tree and release handles */
__declspec(dllexport) int win_kill(void* L) {
    init_lua_api();
    ProcSlot* ps = get_slot(L, 1);
    if (ps) close_slot(ps);
    return 0;
}
