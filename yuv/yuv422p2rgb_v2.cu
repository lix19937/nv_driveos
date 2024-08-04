/**************************************************************
 * @Copyright: 2021-2022 Copyright
 * @Author: lix
 * @Date: 2022-01-10 13:35:47
 * @Last Modified by: lix
 * @Last Modified time: 2022-01-14 14:32:53
 **************************************************************/

#include <cuda_fp16.h>
#include <stdint.h>
#include "opencv2/opencv.hpp"

// https://www.fourcc.org/pixel-format/yuv-i420/
// I420 -> It comprises an NxN Y plane followed by (N/2)x(N/2) U and V planes
// is ThreePlaneYUV2BGR

// y skip 2 line,  uv skip 1 line
// for (int j=rangeBegin; j <rangeEnd; j+=2, y1 += stride*2, u1 += width/2,  v1
// += width/2){
//   auto row1 = dst_data + dst_step * j;
//   auto row2 = row1     + dst_step;

//   const auto y2 = y1 + stride;

//   // x access half w
//   for (int i = 0; i <width/2; i+=1, row1 += 3*2, row2 += 3*2){
//     auto u = u1[i];
//     auto v = v1[i];

//     auto vy01 = y1[2 * i];
//     auto vy11 = y1[2 * i + 1];
//     auto vy02 = y2[2 * i];
//     auto vy12 = y2[2 * i + 1];

//     yuv42xxp2rgb8<bIdx, dcn, true>(u, v, vy01, vy11, vy02, vy12, row1, row2);
//   }
// }

// Coefficients for RGB to YUV420p conversion

// R = 1.164(Y - 16) + 1.596(V - 128)
// G = 1.164(Y - 16) - 0.813(V - 128) - 0.391(U - 128)
// B = 1.164(Y - 16)                  + 2.018(U - 128)
//                   ===>
// R = (1220542(Y - 16) + 1673527(V - 128)                  + (1 << 19)) >> 20
// G = (1220542(Y - 16) - 852492(V - 128) - 409993(U - 128) + (1 << 19)) >> 20
// B = (1220542(Y - 16)                  + 2116026(U - 128) + (1 << 19)) >> 20

namespace {

__device__ __forceinline__ void uvToRGBuv(const uint8_t u, const uint8_t v, int& ruv, int& guv, int& buv) {
  const int ITUR_BT_601_CUB = 2116026;
  const int ITUR_BT_601_CUG = -409993;
  const int ITUR_BT_601_CVG = -852492;
  const int ITUR_BT_601_CVR = 1673527;
  const int ITUR_BT_601_SHIFT = 20;
  const int offset = (1 << (ITUR_BT_601_SHIFT - 1));

  int uu = int(u) - 128;
  int vv = int(v) - 128;
  ruv = offset + ITUR_BT_601_CVR * vv;
  guv = offset + ITUR_BT_601_CVG * vv + ITUR_BT_601_CUG * uu;
  buv = offset + ITUR_BT_601_CUB * uu;
}

template <int dcn>
__device__ __forceinline__ void yRGBuvToRGBA(
    const uint8_t vy, const int ruv, const int guv, const int buv, uint8_t& r, uint8_t& g, uint8_t& b, uint8_t& a) {
  const int ITUR_BT_601_CY = 1220542;
  const int ITUR_BT_601_SHIFT = 20;

  int y = max(0, vy - 16) * ITUR_BT_601_CY;

  auto saturate_cast = [](const int& v) { return (uint8_t)((unsigned)v <= 255 ? v : v > 0 ? 255 : 0); };

  r = saturate_cast((y + ruv) >> ITUR_BT_601_SHIFT);
  g = saturate_cast((y + guv) >> ITUR_BT_601_SHIFT);
  b = saturate_cast((y + buv) >> ITUR_BT_601_SHIFT);

  // follow is comment
  if (dcn == 4) {
    a = uint8_t(0xff);
  }
}

template <int bIdx, int dcn, bool is420>
__device__ __forceinline__ void yuv42xxp2rgb8(
    const uint8_t u,
    const uint8_t v,
    const uint8_t vy01,
    const uint8_t vy11,
    const uint8_t vy02,
    const uint8_t vy12,
    uint8_t* row1,
    uint8_t* row2) {
  int ruv, guv, buv;
  uvToRGBuv(u, v, ruv, guv, buv);

  uint8_t r00, g00, b00, a00, r01, g01, b01, a01;
  yRGBuvToRGBA<dcn>(vy01, ruv, guv, buv, r00, g00, b00, a00);
  yRGBuvToRGBA<dcn>(vy11, ruv, guv, buv, r01, g01, b01, a01);

  row1[2 - bIdx] = r00;
  row1[1] = g00;
  row1[bIdx] = b00;
  if (dcn == 4) {
    row1[3] = a00;
  }

  row1[dcn + 2 - bIdx] = r01;
  row1[dcn + 1] = g01;
  row1[dcn + 0 + bIdx] = b01;
  if (dcn == 4) {
    row1[7] = a01;
  }

  if (is420) {
    uint8_t r10, g10, b10, a10, r11, g11, b11, a11;
    yRGBuvToRGBA<dcn>(vy02, ruv, guv, buv, r10, g10, b10, a10);
    yRGBuvToRGBA<dcn>(vy12, ruv, guv, buv, r11, g11, b11, a11);

    row2[2 - bIdx] = r10;
    row2[1] = g10;
    row2[bIdx] = b10;
    if (dcn == 4) {
      row2[3] = a10;
    }

    row2[dcn + 2 - bIdx] = r11;
    row2[dcn + 1] = g11;
    row2[dcn + 0 + bIdx] = b11;
    if (dcn == 4) {
      row2[7] = a11;
    }
  }
}
} // namespace

template <int bIdx, int uIdx, int yIdx, int dcn>
__global__ void yuv422p2rgb_kernel_v1(
    uint8_t* __restrict__ dst_data, const uint8_t* __restrict__ src_data, const int h, const int w) {
  int j = blockIdx.y * blockDim.y + threadIdx.y;
  int i = blockIdx.x * blockDim.x + threadIdx.x;

  if (i >= w / 2 || j >= h) {
    return;
  }

  // const int uidx = 1 - yIdx + uIdx * 2;
  // const int vidx = (2 + uidx) % 4;

  // int dst_step = dcn * w;
  // int src_step = 2 * w; // scn =2

  auto step_iter = src_step * j;

  auto row = dst_data + (dcn * w) * j + (dcn * 2) * i;

  // 0 2 1 3
  // auto i_iter = i * 4;
  // auto u = src_data[step_iter + i_iter + uidx];
  // auto v = src_data[step_iter + i_iter + vidx];
  // auto vy0 = src_data[step_iter + i_iter + yIdx];
  // auto vy1 = src_data[step_iter + i_iter + yIdx + 2];
  // yuv42xxp2rgb8<bIdx, dcn, false>(u, v, vy0, vy1, 0, 0, row, (uint8_t*)(0));

  // uchar4
  uchar4 uyvy = __ldg((uchar4*)src_data + step_iter / 4 + i);
  yuv42xxp2rgb8<bIdx, dcn, false>(uyvy.x, uyvy.z, uyvy.y, uyvy.w, 0, 0, row, (uint8_t*)(0));
}

int yuv422p2rgb(
    uint8_t* dst_data, /* rgb /bgr */
    int h,
    int w,
    const uint8_t* src_data) {
  int block_w = 1, block_h = 1;
  dim3 grid((w / 2 + block_w - 1) / block_w, (h + block_h - 1) / block_h);
  dim3 block(block_w, block_h);

  yuv422p2rgb_kernel_v1<0, 0, 1, 3><<<grid, block, 0, 0>>>(dst_data, src_data, h, w);

  cudaPeekAtLastError();
  cudaStreamSynchronize(0);
  return 0;
}

int main() {
  auto img_bgr = cv::imread("debug.png");

  int w = img_bgr.cols;
  int h = img_bgr.rows;
  int c = img_bgr.channels();

  ////// Convert from BGR to YUV, Just to get YUV422 data
  cv::Mat img_yuv422(h, w, CV_8UC2, cv::Scalar::all(0));
  cv::cvtColor(img_bgr, img_yuv422, cv::COLOR_BGR2YUV_UYVY);

  ////// YUV422 TO BGR
  cv::Mat img_bgr_gt;
  cv::cvtColor(img_yuv422, img_bgr_gt, cv::COLOR_YUV2BGR_UYVY);
  cv::imwrite("img_bgr_gt.png", img_bgr_gt);

  ////// Byself
  cv::Mat img_bgr_ref(h, w, CV_8UC3, cv::Scalar::all(0));

  //
  void *d_src, *d_dst;
  cudaMalloc(&d_src, h * 2 * w);
  cudaMalloc(&d_dst, h * 3 * w);

  int nbytes = h * 2 * w;
  cudaMemcpy(d_src, img_yuv422.data, nbytes, ::cudaMemcpyHostToDevice);

  yuv422p2rgb((uint8_t*)d_dst, h, w, (const uint8_t*)d_src);

  nbytes = h * 3 * w;
  cudaMemcpy(img_bgr_ref.data, d_dst, nbytes, ::cudaMemcpyDeviceToHost);

  cv::imwrite("img_bgr_ref.png", img_bgr_ref);

  cudaFree(d_src);
  cudaFree(d_dst);

  return 0;
}

/*
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/mnt/d/workspace/opencv-4.9.0/build/install_local/lib
nvcc -std=c++14 -O2 ./yuv422p2rgb.cu  -lopencv_core -lopencv_imgproc -lopencv_highgui -lopencv_imgcodecs \
-I/mnt/d/workspace/opencv-4.9.0/build/install_local/include/opencv4 \
-L/mnt/d/workspace/opencv-4.9.0/build/install_local/lib


*/
