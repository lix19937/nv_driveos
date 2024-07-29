参考模块  Image 2D (nvmimg_2d)  

https://developer.nvidia.com/docs/drive/drive-os/6.0.6/public/drive-os-linux-sdk/common/topics/nvmedia_sample_apps/Image2D_nvmimg_2d_1.html   

主要API NvMedia2DCompose    
   NvSciBufObjGetPixels    

YUV planar 的 crop  resize   可参考 crop_yuv420_planar.cfg, upscale_yuv420_planar.cfg         
YUV packed 的   


对于 BGR 的planar 即 CHW 排布，是否可以参照 YUV planar   
对于 BGR的图像(未进行通道分离)进行crop/resize 是否等价于 BGR分离通道的各自crop/resize，然后合并通道 ？ 
