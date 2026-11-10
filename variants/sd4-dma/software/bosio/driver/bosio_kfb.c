// Built-in Linux 6.12 driver. DMA buffers live for the platform's whole lifetime.
#include <linux/capability.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_reserved_mem.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/vmalloc.h>
#include "../common/bosio_engine.h"
#ifdef MODULE
#error "BOSIO must be built in: outstanding DMA must survive close and timeout"
#endif
struct bosio_device {
    struct miscdevice misc;
    struct mutex mutex;
    struct bo_engine engine;
    void __iomem *regs[3];
    void *arena;
    dma_addr_t dma;
    bool opened;
};
static int hw_read(void *opaque,unsigned int core,__u32 reg,__u32 *value)
{ struct bosio_device *d=opaque;*value=readl(d->regs[core]+reg);return 0; }
static int hw_write(void *opaque,unsigned int core,__u32 reg,__u32 value)
{ struct bosio_device *d=opaque;writel(value,d->regs[core]+reg);return 0; }
static __u64 hw_now(void *opaque) { return ktime_to_us(ktime_get()); }
static void hw_delay(void *opaque,unsigned int us) { usleep_range(us,us+50); }
static void hw_barrier(void *opaque) { dma_wmb();dma_rmb(); }
static int bosio_open(struct inode *inode,struct file *file)
{
    struct bosio_device *d=container_of(file->private_data,struct bosio_device,misc);
    int ret=0;
    if(!capable(CAP_SYS_RAWIO))return -EPERM;
    mutex_lock(&d->mutex);
    if(d->opened)ret=-EBUSY;
    else if(d->engine.poisoned)ret=-EIO;
    else {d->opened=true;file->private_data=d;}
    mutex_unlock(&d->mutex);return ret;
}
static int bosio_release(struct inode *inode,struct file *file)
{
    struct bosio_device *d=file->private_data;
    mutex_lock(&d->mutex);
    /* Never free on close. A timeout cannot cancel an accepted AXI transfer. */
    if(!d->engine.poisoned)bo_stop(&d->engine,1000);
    d->opened=false;
    mutex_unlock(&d->mutex);return 0;
}
static long bosio_ioctl(struct file *file,unsigned int cmd,unsigned long arg)
{
    struct bosio_device *d=file->private_data;
    void __user *u=(void __user *)arg;
    long ret=0;
    if(mutex_lock_interruptible(&d->mutex))return -ERESTARTSYS;
    switch(cmd){
    case BO_GET_INFO: {
        struct bo_info info;
        ret=bo_info(&d->engine,&info);
        if(!ret&&copy_to_user(u,&info,sizeof(info)))ret=-EFAULT;
        break;
    }
    case BO_UPLOAD: {
        struct bo_upload upload;void *tmp;
        if(copy_from_user(&upload,u,sizeof(upload))){ret=-EFAULT;break;}
        if(upload.reserved || upload.data>ULONG_MAX){ret=-EINVAL;break;}
        ret=bo_upload_check(&d->engine,upload.region,upload.offset,upload.bytes);
        if(ret)break;
        tmp=vmemdup_user(u64_to_user_ptr(upload.data),upload.bytes);
        if(IS_ERR(tmp)){ret=PTR_ERR(tmp);break;}
        memcpy(d->arena+bo_offsets[upload.region]+upload.offset,tmp,upload.bytes);
        kvfree(tmp);dma_wmb();break;
    }
    case BO_DOWNLOAD: {
        struct bo_upload download;
        if(copy_from_user(&download,u,sizeof(download))){ret=-EFAULT;break;}
        if(download.reserved || download.data>ULONG_MAX){ret=-EINVAL;break;}
        ret=bo_download_check(&d->engine,download.region,download.offset,download.bytes);
        if(ret)break;
        /* BO_RUN returns only after both masters complete. The mutex also
         * excludes uploads and new jobs while the coherent result is copied. */
        dma_rmb();
        if(copy_to_user(u64_to_user_ptr(download.data),
                        d->arena+bo_offsets[download.region]+download.offset,download.bytes))ret=-EFAULT;
        break;
    }
    case BO_RUN: {
        struct bo_run run;
        if(copy_from_user(&run,u,sizeof(run))){ret=-EFAULT;break;}
        ret=bo_run(&d->engine,&run,d->arena+bo_offsets[BO_DESC0],d->arena+bo_offsets[BO_DESC1]);
        if(copy_to_user(u,&run,sizeof(run)))ret=-EFAULT;
        break;
    }
    case BO_PRESENT: {
        struct bo_present *present=memdup_user(u,sizeof(*present));
        if(IS_ERR(present)){ret=PTR_ERR(present);break;}
        if(present->bank>1)ret=-EINVAL;
        else ret=bo_present(&d->engine,present,d->arena+bo_offsets[BO_SCENE0+present->bank]);
        kfree(present);break;
    }
    case BO_SET_POSE: {
        struct bo_pose *pose=memdup_user(u,sizeof(*pose));
        if(IS_ERR(pose)){ret=PTR_ERR(pose);break;}
        ret=bo_set_pose(&d->engine,pose);kfree(pose);break;
    }
    case BO_STOP: ret=bo_stop(&d->engine,1000);break;
    default: ret=-ENOTTY;
    }
    mutex_unlock(&d->mutex);return ret;
}
static const struct file_operations bosio_fops={
    .owner=THIS_MODULE,.open=bosio_open,.release=bosio_release,
    .unlocked_ioctl=bosio_ioctl,
};
static int bosio_probe(struct platform_device *pdev)
{
    struct device *dev=&pdev->dev;
    struct bosio_device *d;
    struct device_node *node;
    struct reserved_mem *rmem;
    struct bo_info info;
    struct bo_io io;
    int c,ret;
    d=devm_kzalloc(dev,sizeof(*d),GFP_KERNEL);if(!d)return -ENOMEM;
    for(c=0;c<3;c++){
        struct resource *r=platform_get_resource(pdev,IORESOURCE_MEM,c);
        if(!r || resource_size(r)!=0x80 || r->start!=0x20000000+c*0x10000)return -EINVAL;
        d->regs[c]=devm_ioremap_resource(dev,r);if(IS_ERR(d->regs[c]))return PTR_ERR(d->regs[c]);
    }
    node=of_parse_phandle(dev->of_node,"memory-region",0);
    if(!node)return -EINVAL;
    rmem=of_reserved_mem_lookup(node);
    ret=(!rmem || rmem->base!=0xbd000000 || rmem->size!=BO_ARENA_BYTES ||
         !of_property_read_bool(node,"no-map"))?-EINVAL:0;
    of_node_put(node);if(ret)return ret;
    ret=dma_set_mask_and_coherent(dev,DMA_BIT_MASK(32));if(ret)return ret;
    ret=of_reserved_mem_device_init(dev);if(ret)return ret;
    d->arena=dma_alloc_coherent(dev,BO_ARENA_BYTES,&d->dma,GFP_KERNEL);
    if(!d->arena){ret=-ENOMEM;goto release_pool;}
    if(d->dma!=0xbd000000){ret=-EINVAL;goto free_dma;}
    io=(struct bo_io){d,hw_read,hw_write,hw_now,hw_delay,hw_barrier};
    bo_init(&d->engine,&io,(__u32)d->dma);
    ret=bo_info(&d->engine,&info);
    if(ret || info.signature!=0x42533235 || info.capability!=0x44544631 || (info.status&0x15)){
        ret=-ENODEV;goto free_dma;
    }
    for(c=0;c<2;c++)if(!(readl(d->regs[c])&4)){ret=-EBUSY;goto free_dma;}
    memset(d->arena+bo_offsets[BO_SCRATCH],0,BO_SCRATCH_BYTES);
    mutex_init(&d->mutex);
    d->misc=(struct miscdevice){.minor=MISC_DYNAMIC_MINOR,.name="bosio0",.fops=&bosio_fops,.parent=dev,.mode=0600};
    ret=misc_register(&d->misc);if(ret)goto free_dma;
    platform_set_drvdata(pdev,d);
    dev_info(dev,"BOSIO ABI3: dual projectors + BS25, frame-atomic software pose, 16MiB DMA\n");
    return 0;
free_dma:
    dma_free_coherent(dev,BO_ARENA_BYTES,d->arena,d->dma);
release_pool:
    of_reserved_mem_device_release(dev);return ret;
}
static const struct of_device_id bosio_of_match[]={{.compatible="oryukdo,kfb-bosio-v1"},{}};
static struct platform_driver bosio_driver={
    .probe=bosio_probe,
    .driver={.name="bosio-kfb",.of_match_table=bosio_of_match,.suppress_bind_attrs=true},
};
builtin_platform_driver(bosio_driver);
MODULE_DESCRIPTION("ORYUKDO KFB BOSIO controlled DMA and dual projection");
MODULE_LICENSE("GPL");
