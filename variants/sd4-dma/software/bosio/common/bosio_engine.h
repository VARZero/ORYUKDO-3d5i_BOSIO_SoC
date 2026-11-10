#ifndef BOSIO_ENGINE_H
#define BOSIO_ENGINE_H
#include "../include/bosio_uapi.h"
struct bo_io {
    void *opaque;
    int (*read)(void *, unsigned int, __u32, __u32 *);
    int (*write)(void *, unsigned int, __u32, __u32);
    __u64 (*now_us)(void *);
    void (*delay_us)(void *, unsigned int);
    void (*memory_fence)(void *);
};
struct bo_engine {
    struct bo_io io;
    __u32 dma_base;
    int active, poisoned, configured;
    __u32 resolution, camera[180];
};
extern const __u32 bo_offsets[BO_REGIONS], bo_sizes[BO_REGIONS];
void bo_init(struct bo_engine *, const struct bo_io *, __u32);
int bo_info(struct bo_engine *, struct bo_info *);
int bo_upload_check(struct bo_engine *, unsigned int, __u32, __u32);
int bo_download_check(struct bo_engine *, unsigned int, __u32, __u32);
int bo_run(struct bo_engine *, struct bo_run *, const __u32 *, const __u32 *);
int bo_present(struct bo_engine *, const struct bo_present *, const __u32 *);
int bo_stop(struct bo_engine *, unsigned int);
int bo_set_pose(struct bo_engine *, const struct bo_pose *);
#endif
