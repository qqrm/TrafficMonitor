#ifndef TM_PLUGIN_ABI_H
#define TM_PLUGIN_ABI_H

/* Stable C ABI for TrafficMonitor plugins.
 * Every plugin exports:
 *   int32_t tm_plugin_abi_version(void);
 *   const TMPluginVTable* tm_plugin_vtable(void);
 */

#define TM_PLUGIN_ABI_VERSION 1

typedef struct TMPlugin TMPlugin;
typedef struct TMPluginItem TMPluginItem;

typedef struct TMRect {
    int x;
    int y;
    int w;
    int h;
} TMRect;

typedef struct TMColor {
    unsigned char r;
    unsigned char g;
    unsigned char b;
    unsigned char a;
} TMColor;

/* Opaque surface handle supplied by the host. */
typedef struct TMSurface TMSurface;

typedef struct TMPluginVTable {
    /* lifecycle */
    void (*destroy)(TMPlugin* self);
    void (*initialize)(TMPlugin* self, void* host_functions);
    void (*uninitialize)(TMPlugin* self);

    /* items */
    int (*get_item_count)(TMPlugin* self);
    TMPluginItem* (*get_item)(TMPlugin* self, int index);

    /* data */
    void (*data_required)(TMPlugin* self);

    /* item interface */
    const char* (*item_name)(TMPluginItem* self);
    const char* (*item_id)(TMPluginItem* self);
    const char* (*item_value_text)(TMPluginItem* self);
    const char* (*item_tooltip)(TMPluginItem* self);
    float (*item_graph_value)(TMPluginItem* self);
    void (*draw_item)(TMPluginItem* self, TMSurface* surface, TMRect rect, int dark_mode);
} TMPluginVTable;

#ifdef __cplusplus
extern "C" {
#endif

int32_t tm_plugin_abi_version(void);
const TMPluginVTable* tm_plugin_vtable(void);

#ifdef __cplusplus
}
#endif

#endif /* TM_PLUGIN_ABI_H */