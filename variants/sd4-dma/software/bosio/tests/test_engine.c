#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include "../common/bosio_demo.h"
_Static_assert(sizeof(struct bo_upload)==24,"upload ABI");
_Static_assert(sizeof(struct bo_run)==40,"run ABI");
_Static_assert(sizeof(struct bo_present)==736,"present ABI");
_Static_assert(sizeof(struct bo_info)==36,"info ABI");
struct mock {unsigned reads[2],done[2],delay[2],started[2],writes;__u64 now;};
static int rd(void *p,unsigned c,__u32 r,__u32 *v)
{
    struct mock *m=p;*v=0;
    if(c<2&&r==0){
        if(m->started[c]&&!m->done[c]&&++m->reads[c]>=m->delay[c]){m->done[c]=1;*v=6;}
        else *v=m->started[c]&&!m->done[c]?0:4;
    }
    if(c<2&&r==0x5c)*v=1024;
    return 0;
}
static int wr(void *p,unsigned c,__u32 r,__u32 v)
{struct mock *m=p;m->writes++;if(c<2&&r==0&&v==1)m->started[c]=1;return 0;}
static __u64 now(void *p){return ((struct mock*)p)->now;}
static void delay(void *p,unsigned n){((struct mock*)p)->now+=n;}
static void fence(void *p){(void)p;}
int main(void)
{
    unsigned order,checks=0;struct bo_engine e;struct mock m;__u32 d[2][18];
    struct bo_io io={&m,rd,wr,now,delay,fence};
    struct bo_run j={.scene_words=BO_DEMO_WORDS,.texture_words=2,.jobs={1,1},.timeout_ms=1};
    for(order=0;order<2;order++){
        memset(&m,0,sizeof(m));m.delay[order]=1;m.delay[1-order]=7;
        bo_init(&e,&io,0xbd000000);bo_demo_descriptor(d[0],0,3);bo_demo_descriptor(d[1],1,3);
        assert(!bo_run(&e,&j,d[0],d[1]));assert(m.done[0]&&m.done[1]);
        assert(j.cells[0]==1024&&j.cells[1]==1024);checks++;
    }
    memset(&m,0,sizeof(m));bo_init(&e,&io,0xbd000000);
    assert(bo_upload_check(&e,BO_REGIONS,0,4)==-EINVAL);checks++;
    assert(bo_upload_check(&e,BO_TEXTURE,0xfffffffc,8)==-EINVAL);checks++;
    assert(bo_upload_check(&e,BO_TEXTURE,1,4)==-EINVAL);checks++;
    assert(bo_upload_check(&e,BO_TEXTURE,0,0)==-EINVAL);checks++;
    assert(bo_upload_check(&e,BO_TEXTURE,bo_sizes[0]-4,8)==-EINVAL);checks++;
    assert(!bo_upload_check(&e,BO_TEXTURE,bo_sizes[0]-4,4));checks++;
    d[0][1]=0;assert(bo_run(&e,&j,d[0],d[1])==-EINVAL);checks++;bo_demo_descriptor(d[0],0,3);
    d[0][0]=0xffffffff;assert(bo_run(&e,&j,d[0],d[1])==-EINVAL);checks++;bo_demo_descriptor(d[0],0,3);
    d[0][3]=2048;d[0][4]=0xffffffff;assert(bo_run(&e,&j,d[0],d[1])==-EINVAL);checks++;bo_demo_descriptor(d[0],0,3);
    assert(m.writes==0);checks++;
    j.jobs[0]=j.jobs[1]=0;assert(!bo_run(&e,&j,d[0],d[1])&&m.writes==0);checks++;
    j.jobs[0]=j.jobs[1]=1;e.active=0;assert(bo_run(&e,&j,d[0],d[1])==-EBUSY);checks++;
    assert(bo_upload_check(&e,BO_SCENE0,0,4)==-EBUSY);checks++;
    assert(!bo_upload_check(&e,BO_SCRATCH,0,BO_SCRATCH_BYTES));checks++;
    assert(!bo_download_check(&e,BO_SCRATCH,0,BO_SCRATCH_BYTES));checks++;
    assert(bo_download_check(&e,BO_SCENE0,0,4)==-EINVAL);checks++;
    assert(bo_download_check(&e,BO_SCRATCH,BO_SCRATCH_BYTES-4,8)==-EINVAL);checks++;
    assert(bo_download_check(&e,BO_SCRATCH,0xfffffffc,8)==-EINVAL);checks++;
    j.bank=2;j.scene_words=BO_SCRATCH_BYTES/4+16;
    assert(bo_run(&e,&j,d[0],d[1])==-EINVAL);checks++;
    j.scene_words=BO_DEMO_WORDS;j.jobs[0]=j.jobs[1]=0;
    assert(!bo_run(&e,&j,d[0],d[1]));checks++;
    for(unsigned a=0;a<BO_REGIONS;a++){
        assert(bo_offsets[a]+bo_sizes[a]<=BO_ARENA_BYTES);
        for(unsigned b=a+1;b<BO_REGIONS;b++)
            assert(bo_offsets[a]+bo_sizes[a]<=bo_offsets[b]||bo_offsets[b]+bo_sizes[b]<=bo_offsets[a]);
    }
    checks++;
    j.bank=0;j.jobs[0]=j.jobs[1]=1;
    e.active=-1;m.delay[0]=m.delay[1]=10000;
    assert(bo_run(&e,&j,d[0],d[1])==-ETIMEDOUT);assert(e.poisoned);checks++;
    assert(bo_upload_check(&e,BO_DESC0,0,4)==-EIO);checks++;
    assert(bo_run(&e,&j,d[0],d[1])==-EIO);checks++;
    assert(bo_stop(&e,1)==-EIO);checks++;
    assert(bo_download_check(&e,BO_SCRATCH,0,4)==-EIO);checks++;
    printf("PASS ENGINE checks=%u completion-order/bounds/overflow/noop/active/timeout UAPI=24,40,736,36\n",checks);
    return 0;
}
