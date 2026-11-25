// Test-only plugin, built against the actual host ABI. Each DLL has a distinct ID.
#include <windows.h>
#include "PluginInterface.h"

#ifndef PROBE_INDEX
#error PROBE_INDEX must be 0..3
#endif

namespace {
constexpr const wchar_t* ids[] = {
    L"hotreload_probe_0", L"hotreload_probe_1",
    L"hotreload_probe_2", L"hotreload_probe_3"
};

void Record(const char* event)
{
    wchar_t path[32768];
    DWORD n = GetEnvironmentVariableW(L"TM_HOT_RELOAD_TRACE", path, ARRAYSIZE(path));
    if (!n || n >= ARRAYSIZE(path))
        return;
    HANDLE file = CreateFileW(path, FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return;
    char line[64];
    int length = wsprintfA(line, "%d %s\r\n", PROBE_INDEX, event);
    DWORD written;
    WriteFile(file, line, length, &written, nullptr);
    CloseHandle(file);
}

bool taskbar = false;
bool drawn = false;
bool settings = false;
bool initialized = false;

class ProbeItem final : public IPluginItem
{
public:
    const wchar_t* GetItemName() const override { return ids[PROBE_INDEX]; }
    const wchar_t* GetItemId() const override { return ids[PROBE_INDEX]; }
    const wchar_t* GetItemLableText() const override { return L"Probe"; }
    const wchar_t* GetItemValueText() const override { return L"1"; }
    const wchar_t* GetItemValueSampleText() const override { return L"1"; }
    bool IsCustomDraw() const override { return true; }
    int GetItemWidth() const override { return 32; }
    void DrawItem(void*, int, int, int w, int h, bool) override
    {
        if (taskbar && !drawn && w > 0 && h > 0) {
            drawn = true;
            Record("draw");
        }
    }
    bool DrawItemEx(IPluginDrawer*, int, int, int w, int h, bool) override
    {
        DrawItem(nullptr, 0, 0, w, h, false);
        return false;
    }
};

class ProbePlugin final : public ITMPlugin
{
    ProbeItem item;
public:
    IPluginItem* GetItem(int index) override { return index == 0 ? &item : nullptr; }
    void DataRequired() override {}
    const wchar_t* GetInfo(PluginInfoIndex) override { return ids[PROBE_INDEX]; }
    void OnInitialize(ITrafficMonitor*) override
    {
        Record(initialized ? "duplicate-init" : "load");
        initialized = true;
    }
    void OnExtenedInfo(ExtendedInfoIndex index, const wchar_t* value) override
    {
        if (index == EI_DRAW_TASKBAR_WND)
            taskbar = value && value[0] == L'1';
        if (index == EI_TASKBAR_WND_NET_SPEED_SHORT_MODE && !settings) {
            settings = true;
            Record("settings");
        }
    }
};
ProbePlugin plugin;
}

extern "C" __declspec(dllexport) ITMPlugin* TMPluginGetInstance()
{
    return &plugin;
}
