#ifndef BOSIO_UAPI_H
#define BOSIO_UAPI_H
#include <linux/types.h>
#include <linux/ioctl.h>
#define BO_ABI 3
#define BO_ARENA_BYTES 0x1000000u
#define BO_MAX_WORDS 1084816u
#define BO_MAX_JOBS 64u
#define BO_DESC_WORDS 18u
#define BO_HEADER_WORDS 4476u
#define BO_TILE_WORDS 256u
/* Scratch is disjoint from both scanout banks and never presented. */
#define BO_SCRATCH_BYTES 0x40000u
enum { BO_TEXTURE, BO_DESC0, BO_DESC1, BO_SCENE0, BO_SCENE1, BO_SCRATCH, BO_REGIONS };
struct bo_upload { __u32 region, offset, bytes, reserved; __aligned_u64 data; };
struct bo_run {
    __u32 bank, scene_words, texture_words, jobs[2], timeout_ms;
    __u32 status[2], cells[2];
};
struct bo_present {
    __u32 bank, scene_words, resolution, timeout_ms;
    __u32 camera[180];
};
struct bo_info {
    __u32 abi, signature, capability, status, active_base;
    __s32 active_bank;
    __u32 poisoned, max_jobs, max_scene_words;
};
struct bo_pose { __u32 timeout_ms; __u32 camera[180]; };
#define BO_GET_INFO _IOR('B', 0x40, struct bo_info)
#define BO_UPLOAD _IOW('B', 0x41, struct bo_upload)
#define BO_RUN _IOWR('B', 0x42, struct bo_run)
#define BO_PRESENT _IOW('B', 0x43, struct bo_present)
#define BO_STOP _IO('B', 0x44)
#define BO_DOWNLOAD _IOW('B', 0x45, struct bo_upload)
#define BO_SET_POSE _IOW('B', 0x46, struct bo_pose)
#endif
