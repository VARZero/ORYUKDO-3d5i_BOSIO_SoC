#ifndef BOSIO_DEMO_H
#define BOSIO_DEMO_H
#include "bosio_engine.h"
#define BO_DEMO_WORDS 4992u
static inline void bo_demo_scene(__u32 *scene)
{
    unsigned int i;
    for(i=0;i<BO_DEMO_WORDS;i++)scene[i]=0;
    /* Display stream is RGB888: use an explicit RGB palette. */
    for(i=0;i<256;i++)scene[i]=(((i>>5)*255/7)<<16)|((((i>>2)&7)*255/7)<<8)|((i&3)*255/3);
    for(i=256;i<BO_HEADER_WORDS;i++)scene[i]=0xffffffffu;
    for(i=0;i<211;i++)scene[256+i]=0;
    for(i=211;i<422;i++)scene[256+i]=1024;
    for(i=BO_HEADER_WORDS;i<BO_DEMO_WORDS;i++)scene[i]=0xcccccccc;
}
static inline void bo_demo_descriptor(__u32 *d,unsigned int core,unsigned int index)
{
    unsigned int i;for(i=0;i<18;i++)d[i]=0;
    d[0]=core;d[1]=BO_HEADER_WORDS+core*BO_TILE_WORDS;
    d[2]=d[3]=d[4]=1;
    d[5]=(index<<8)|1; /* Clear fallback; valid projection must overwrite this. */
    d[14]=1; /* Constant u=v=0, denominator=1: sample actual RGB texture. */
}
static inline void bo_demo_camera(__u32 *camera)
{
    unsigned int i;for(i=0;i<180;i++)camera[i]=0;
    for(i=0;i<60;i++)camera[i*3]=0xffffffffu;
    camera[0]=640;camera[1]=0xffffffffu;camera[3]=1;camera[6]=1;
    camera[9]=(__u32)-641;camera[10]=1;camera[12]=1;camera[15]=1;
}
#endif
