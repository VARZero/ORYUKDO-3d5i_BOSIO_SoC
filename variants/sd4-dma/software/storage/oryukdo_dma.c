// SPDX-License-Identifier: GPL-2.0-only
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of_dma.h>
#include <linux/platform_device.h>
#include "virt-dma.h"

struct or_desc {
 struct virt_dma_desc vd;
 dma_addr_t src,dst;
 u32 bytes,pattern,op;
};
struct or_dma {
 struct dma_device dev;
 struct virt_dma_chan channel;
 struct or_desc *active;
 void __iomem *regs;
 int irq;
};
static struct or_dma *to_or(struct dma_chan *c)
{ return container_of(to_virt_chan(c),struct or_dma,channel); }
static void or_free(struct virt_dma_desc *v)
{ kfree(container_of(v,struct or_desc,vd)); }
static void or_next(struct or_dma *d)
{
 struct virt_dma_desc *v;
 if(d->active) return;
 v=vchan_next_desc(&d->channel);
 if(!v) return;
 list_del(&v->node);d->active=container_of(v,struct or_desc,vd);
 writel(2,d->regs+20);
 writel(lower_32_bits(d->active->src),d->regs);
 writel(lower_32_bits(d->active->dst),d->regs+4);
 writel(d->active->bytes,d->regs+8);
 writel(d->active->pattern,d->regs+12);
 dma_wmb();writel(d->active->op|BIT(8),d->regs+16);
}
static irqreturn_t or_irq(int irq,void *arg)
{
 struct or_dma *d=arg;u32 status=readl(d->regs+20);unsigned long flags;
 if(!(status&2)) return IRQ_NONE;
 writel(2,d->regs+20);
 spin_lock_irqsave(&d->channel.lock,flags);
 if(d->active) {
  if(status&4) {d->active->vd.tx_result.result=DMA_TRANS_ABORTED;d->active->vd.tx_result.residue=d->active->bytes;}
  dma_rmb();vchan_cookie_complete(&d->active->vd);d->active=NULL;
 }
 or_next(d);spin_unlock_irqrestore(&d->channel.lock,flags);
 return IRQ_HANDLED;
}
static struct dma_async_tx_descriptor *or_prep(struct dma_chan *c,dma_addr_t dst,
 dma_addr_t src,size_t len,int value,u32 op,unsigned long flags)
{
 struct or_dma *d=to_or(c);struct or_desc *v;
 if(!len || len>U32_MAX || ((dst|len|(op==1?src:0))&3)) return NULL;
 if(dst<0x80000000ULL || (u64)dst+len>0xc0000000ULL ||
    (op==1 && (src<0x80000000ULL || (u64)src+len>0xc0000000ULL ||
               ((u64)src<(u64)dst+len && (u64)dst<(u64)src+len)))) return NULL;
 v=kzalloc(sizeof(*v),GFP_NOWAIT);if(!v) return NULL;
 v->src=src;v->dst=dst;v->bytes=len;v->op=op;v->pattern=(value&255)*0x01010101U;
 return vchan_tx_prep(&d->channel,&v->vd,flags);
}
static struct dma_async_tx_descriptor *or_copy(struct dma_chan *c,dma_addr_t dst,
 dma_addr_t src,size_t len,unsigned long flags)
{return or_prep(c,dst,src,len,0,1,flags);}
static struct dma_async_tx_descriptor *or_fill(struct dma_chan *c,dma_addr_t dst,
 int value,size_t len,unsigned long flags)
{return or_prep(c,dst,0,len,value,2,flags);}
static void or_issue(struct dma_chan *c)
{
 struct or_dma *d=to_or(c);unsigned long flags;
 spin_lock_irqsave(&d->channel.lock,flags);
 if(vchan_issue_pending(&d->channel)) or_next(d);
 spin_unlock_irqrestore(&d->channel.lock,flags);
}
static int or_terminate(struct dma_chan *c)
{
 struct or_dma *d=to_or(c);unsigned long flags;LIST_HEAD(head);
 spin_lock_irqsave(&d->channel.lock,flags);
 if(d->active) {spin_unlock_irqrestore(&d->channel.lock,flags);return -EBUSY;}
 vchan_get_all_descriptors(&d->channel,&head);
 spin_unlock_irqrestore(&d->channel.lock,flags);
 vchan_dma_desc_free_list(&d->channel,&head);return 0;
}
static void or_sync(struct dma_chan *c)
{ struct or_dma *d=to_or(c);synchronize_irq(d->irq);vchan_synchronize(&d->channel); }
static enum dma_status or_status(struct dma_chan *c,dma_cookie_t cookie,struct dma_tx_state *state)
{return dma_cookie_status(c,cookie,state);}
static int or_alloc(struct dma_chan *c) {return 0;}
static void or_release(struct dma_chan *c)
{if(WARN_ON(or_terminate(c))) return;vchan_free_chan_resources(to_virt_chan(c));}
static struct dma_chan *or_xlate(struct of_phandle_args *spec,struct of_dma *ofdma)
{
 struct or_dma *d=ofdma->of_dma_data;
 if(spec->args_count!=1 || spec->args[0]) return NULL;
 return dma_get_slave_channel(&d->channel.chan);
}
static int or_probe(struct platform_device *pdev)
{
 struct or_dma *d;int ret;
 d=devm_kzalloc(&pdev->dev,sizeof(*d),GFP_KERNEL);if(!d) return -ENOMEM;
 d->regs=devm_platform_ioremap_resource(pdev,0);if(IS_ERR(d->regs)) return PTR_ERR(d->regs);
 d->irq=platform_get_irq(pdev,0);if(d->irq<0) return d->irq;
 ret=dma_set_mask_and_coherent(&pdev->dev,DMA_BIT_MASK(32));if(ret) return ret;
 INIT_LIST_HEAD(&d->dev.channels);d->dev.dev=&pdev->dev;
 dma_cap_set(DMA_MEMCPY,d->dev.cap_mask);dma_cap_set(DMA_MEMSET,d->dev.cap_mask);
 d->dev.copy_align=2;d->dev.fill_align=2;
 d->dev.device_alloc_chan_resources=or_alloc;d->dev.device_free_chan_resources=or_release;
 d->dev.device_prep_dma_memcpy=or_copy;d->dev.device_prep_dma_memset=or_fill;
 d->dev.device_issue_pending=or_issue;d->dev.device_tx_status=or_status;
 d->dev.device_terminate_all=or_terminate;d->dev.device_synchronize=or_sync;
 vchan_init(&d->channel,&d->dev);d->channel.desc_free=or_free;
 ret=devm_request_irq(&pdev->dev,d->irq,or_irq,0,dev_name(&pdev->dev),d);if(ret) return ret;
 ret=dma_async_device_register(&d->dev);if(ret) return ret;
 ret=of_dma_controller_register(pdev->dev.of_node,or_xlate,d);
 if(ret) dma_async_device_unregister(&d->dev);
 return ret;
}
static const struct of_device_id or_match[]={ {.compatible="oryukdo,dma-v1"},{ } };
static struct platform_driver or_driver={.probe=or_probe,
 .driver={.name="oryukdo-dma",.of_match_table=or_match,.suppress_bind_attrs=true}};
builtin_platform_driver(or_driver);
MODULE_LICENSE("GPL");
