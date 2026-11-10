#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include "../common/bosio_demo.h"
static void call(int fd,unsigned long op,void *arg)
{if(ioctl(fd,op,arg)<0){perror("bosio ioctl");exit(1);}}
static void upload(int fd,unsigned region,const void *data,unsigned bytes)
{struct bo_upload u={.region=region,.bytes=bytes,.data=(uintptr_t)data};call(fd,BO_UPLOAD,&u);}
int main(int argc,char **argv)
{
    int fd;struct bo_info info;
    if(argc!=2 || (strcmp(argv[1],"info")&&strcmp(argv[1],"demo"))){
        fprintf(stderr,"usage: bosioctl info|demo\n");return 2;
    }
    fd=open("/dev/bosio0",O_RDWR|O_CLOEXEC);if(fd<0){perror("/dev/bosio0");return 1;}
    call(fd,BO_GET_INFO,&info);
    printf("BOSIO ABI=%u signature=%08x active=%d poison=%u\n",info.abi,info.signature,info.active_bank,info.poisoned);
    if(!strcmp(argv[1],"demo")){
        __u32 scene[BO_DEMO_WORDS],desc[2][18],texture[2]={0xff0000,0x00ff00};
        struct bo_run run={.bank=0,.scene_words=BO_DEMO_WORDS,.texture_words=2,.jobs={1,1},.timeout_ms=30000};
        struct bo_present present={.bank=0,.scene_words=BO_DEMO_WORDS,.resolution=2,.timeout_ms=30000};
        bo_demo_scene(scene);bo_demo_descriptor(desc[0],0,3);bo_demo_descriptor(desc[1],1,3);bo_demo_camera(present.camera);
        upload(fd,BO_SCENE0,scene,sizeof(scene));upload(fd,BO_TEXTURE,texture,sizeof(texture));
        upload(fd,BO_DESC0,desc[0],sizeof(desc[0]));upload(fd,BO_DESC1,desc[1],sizeof(desc[1]));
        call(fd,BO_RUN,&run);
        printf("PROJECT status=%u,%u cells=%u,%u\n",run.status[0],run.status[1],run.cells[0],run.cells[1]);
        call(fd,BO_PRESENT,&present);
        puts("DISPLAY_ACTIVE: left red / right green; press Enter to stop");getchar();
        call(fd,BO_STOP,NULL);
    }
    close(fd);return 0;
}
