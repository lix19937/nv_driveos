

https://blog.csdn.net/hjxu2016/article/details/107959431   

opencv yuv420p 即 YUV_I420   
I420的排列为 前面 hw字节都是Y，再排序U，总字节长度是 WH/4，再排序V，总字节长度是 W*H/4    
属于 YYYY UU VV  


yuv420 crop   
https://blog.csdn.net/Magic_frank/article/details/70941111    



https://en.wikipedia.org/wiki/YUV  

420p  plane   https://fourcc.org/pixel-format/yuv-i420/  
422p  packed     
jpeg  https://docs.fileformat.com/image/jpeg/   


 pitchlinear and blocklinear  
 https://forums.developer.nvidia.com/t/pitch-linear-memory/15526    
 https://forums.developer.nvidia.com/t/whats-the-difference-between-layout-pitch-and-layout-blocklinear/54272    

resize 函数 opencv 中  modules\imgproc\src\resize.cpp   
resizeNN
ResizeFunc   


bgr   
![debug](https://github.com/user-attachments/assets/fd08ea05-126c-4e4a-9cfc-570f0ae70094)    

yuv420   
![img_yuv420](https://github.com/user-attachments/assets/a19d7d42-96e6-4c3d-b6f6-b44a6ced6fb2)

![image](https://github.com/user-attachments/assets/2ded97ea-8559-4ae3-a296-e5f612a4ac0f)
