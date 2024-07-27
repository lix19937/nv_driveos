## https://ephen.me/2017/VSCode_PlantUML/

```plantuml
scale 900 width 

interface data_CompressedImage
NODE NVDEC

NODE NVENC
NODE SYNC
NODE ToBGR_CAT

data_CompressedImage-->NVDEC:jpeg:1 topic
NVDEC-->data_to_REC:BGR:1 topic

data_Camera5400K-->SYNC:YUV422:4 topic
SYNC-->ToBGR_CAT
ToBGR_CAT-->data_to_NNI:BGR:1 topic

ToBGR_CAT-->data_to_Replay:BGR:1 topic

data_to_Replay-->NVENC:BGR:1 topic

NVENC-->data_CompressedImage_to_IMP:jpeg:1 topic

```
